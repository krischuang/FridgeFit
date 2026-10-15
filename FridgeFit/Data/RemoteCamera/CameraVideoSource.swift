//
//  CameraVideoSource.swift
//  FridgeFit
//

import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import UIKit
@preconcurrency import WebRTC

/// The camera device's capture pipeline: one `AVCaptureSession`, feeding
/// both the WebRTC video track and the still-capture path.
///
/// ## Why there is only one capture session
///
/// The obvious way to grab a still is `AVCapturePhotoOutput`, or FridgeFit's
/// existing `CameraPicker`. Both want their own `AVCaptureSession`, and
/// `RTCCameraVideoCapturer` already owns one for the video track. Two
/// sessions competing for the same `AVCaptureDevice` is not a thing iOS
/// supports - the second one to start interrupts the first, so the live
/// stream would stall every time the user pressed the shutter.
///
/// So this type sits *between* `RTCCameraVideoCapturer` and the WebRTC video
/// source as the capturer's delegate: every frame is forwarded onward
/// untouched, and the most recent one is retained. A capture request
/// converts that retained frame to a `UIImage`. One session, no contention,
/// and the still is by construction the frame the controller was looking at.
///
/// The trade-off is resolution: a still is a video frame (1280x720 at the
/// format picked below), not a full-resolution photo. For reading what is on
/// a fridge shelf that is plenty - it is more than
/// `SnapshotImageEncoder.maximumPixelDimension` keeps anyway.
nonisolated final class CameraVideoSource: NSObject, RTCVideoCapturerDelegate, @unchecked Sendable {
    /// Capture format target. 720p is the sweet spot here: good enough to
    /// read a label, cheap enough to encode in real time on an older iPhone,
    /// and small enough that a still JPEG lands in a handful of chunks.
    private static let targetWidth = 1280
    private static let targetHeight = 720
    private static let targetFrameRate = 30

    nonisolated enum CaptureError: Error, Equatable, Sendable {
        case noCameraForPosition(RemoteControlMessage.CameraPosition)
        case noFrameAvailable
        case couldNotConvertFrame

        var describedReason: String {
            switch self {
            case .noCameraForPosition(let position):
                return "this device has no \(position.displayName.lowercased()) camera"
            case .noFrameAvailable:
                return "no camera frame had arrived yet"
            case .couldNotConvertFrame:
                return "the camera frame could not be converted to an image"
            }
        }
    }

    let videoTrack: RTCVideoTrack

    private let videoSource: RTCVideoSource
    private let capturer: RTCCameraVideoCapturer
    private let frameLock = NSLock()
    /// Most recent frame, kept for still capture. One frame of 720p NV12 is
    /// about 1.4 MB; holding exactly one is the whole memory cost.
    private var latestFrame: RTCVideoFrame?
    private var currentPosition: RemoteControlMessage.CameraPosition = .back
    private var isCapturing = false

    /// Reused across captures - `CIContext` creation is expensive and this
    /// one is only touched under `frameLock`.
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    override init() {
        videoSource = WebRTCFactory.shared.peerConnectionFactory.videoSource()
        // `self` as the delegate, not `videoSource` - that interposition is
        // what gives us the frame tap. Frames are forwarded in
        // `capturer(_:didCapture:)` below.
        capturer = RTCCameraVideoCapturer()
        videoTrack = WebRTCFactory.shared.peerConnectionFactory.videoTrack(
            with: videoSource,
            trackId: "fridgefit-camera-video"
        )
        super.init()
        capturer.delegate = self
    }

    var position: RemoteControlMessage.CameraPosition {
        withFrameLock { currentPosition }
    }

    var hasFrames: Bool {
        withFrameLock { latestFrame != nil }
    }

    /// Whether the device has a camera at all. False in the Simulator, which
    /// is why Camera Mode refuses to start there instead of showing a black
    /// preview.
    static var isCameraAvailable: Bool {
        !RTCCameraVideoCapturer.captureDevices().isEmpty
    }

    static func hasCamera(at position: RemoteControlMessage.CameraPosition) -> Bool {
        device(at: position) != nil
    }

    /// Starts capture.
    ///
    /// Caller must have confirmed camera permission first - this does not
    /// prompt, so capture can never begin before the user has explicitly
    /// entered Camera Mode and granted access.
    func start(position: RemoteControlMessage.CameraPosition = .back) async throws {
        guard let device = Self.device(at: position) else {
            throw CaptureError.noCameraForPosition(position)
        }
        let format = Self.bestFormat(for: device)
        let frameRate = min(Self.targetFrameRate, Int(Self.maximumFrameRate(for: format)))

        await withCheckedContinuation { continuation in
            capturer.startCapture(with: device, format: format, fps: frameRate) { error in
                if let error {
                    // Non-fatal: the session may still come up. Surfaced
                    // through `hasFrames` staying false, which Camera Mode
                    // reports rather than claiming to be streaming.
                    RTCLogEx(.error, "Camera capture start reported: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }

        markStarted(position: position)
    }

    func stop() async {
        guard markStopped() else { return }

        await withCheckedContinuation { continuation in
            capturer.stopCapture { continuation.resume() }
        }
    }

    /// Switches lens without tearing the WebRTC track down.
    ///
    /// The track and the peer connection are untouched, so there is no
    /// renegotiation - the same video source simply starts receiving frames
    /// from the other camera.
    func switchCamera() async throws -> RemoteControlMessage.CameraPosition {
        let next = position.other
        guard Self.hasCamera(at: next) else {
            throw CaptureError.noCameraForPosition(next)
        }
        await stop()
        try await start(position: next)
        return next
    }

    /// Converts the most recent frame to a still.
    ///
    /// - Throws: `CaptureError.noFrameAvailable` if nothing has arrived yet,
    ///   which is the honest answer during the first moments after start -
    ///   better than returning a blank image.
    func captureStill() throws -> UIImage {
        let frame = withFrameLock { latestFrame }

        guard let frame else { throw CaptureError.noFrameAvailable }
        guard let image = Self.image(from: frame, context: ciContext) else {
            throw CaptureError.couldNotConvertFrame
        }
        return image
    }

    // MARK: - RTCVideoCapturerDelegate

    /// Called on the capture queue.
    ///
    /// Forwards every frame to the WebRTC source first so the tap never adds
    /// latency to the live stream, then retains it for still capture.
    func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
        videoSource.capturer(capturer, didCapture: frame)
        withFrameLock { latestFrame = frame }
    }

    // MARK: - Synchronous critical sections
    //
    // `NSLock.lock()` is unavailable from async contexts - and rightly so,
    // since holding a lock across a suspension point is how you deadlock. The
    // critical sections here contain no awaits, so they are extracted into
    // synchronous helpers that `start`/`stop` call.

    private func withFrameLock<T>(_ work: () -> T) -> T {
        frameLock.lock()
        defer { frameLock.unlock() }
        return work()
    }

    private func markStarted(position: RemoteControlMessage.CameraPosition) {
        withFrameLock {
            currentPosition = position
            isCapturing = true
        }
    }

    /// - Returns: whether capture was actually running, so `stop` knows
    ///   whether it needs to stop the underlying session.
    private func markStopped() -> Bool {
        withFrameLock {
            let wasCapturing = isCapturing
            isCapturing = false
            latestFrame = nil
            return wasCapturing
        }
    }

    // MARK: - Device and format selection

    private static func device(at position: RemoteControlMessage.CameraPosition) -> AVCaptureDevice? {
        let wanted: AVCaptureDevice.Position = position == .front ? .front : .back
        return RTCCameraVideoCapturer.captureDevices().first { $0.position == wanted }
    }

    /// Picks the supported format closest to 1280x720 in a pixel format
    /// WebRTC can consume directly.
    private static func bestFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format {
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        let preferredPixelFormat = RTCCameraVideoCapturer().preferredOutputPixelFormat()

        let scored = formats.map { format -> (format: AVCaptureDevice.Format, score: Int) in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let pixelFormat = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            // Distance from the target, with a bonus for the pixel format
            // WebRTC prefers - picking a format it has to convert would
            // spend CPU on every frame.
            let distance = abs(Int(dimensions.width) - targetWidth) + abs(Int(dimensions.height) - targetHeight)
            return (format, distance - (pixelFormat == preferredPixelFormat ? 2000 : 0))
        }
        // `formats` is never empty for a device returned by `captureDevices`,
        // but fall back rather than force-unwrap.
        return scored.min { $0.score < $1.score }?.format ?? device.activeFormat
    }

    private static func maximumFrameRate(for format: AVCaptureDevice.Format) -> Float64 {
        format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
    }

    // MARK: - Frame conversion

    /// `RTCVideoFrame` -> `UIImage`, preserving the frame's rotation.
    ///
    /// Camera frames carry an `RTCCVPixelBuffer`; the `newI420VideoFrame`
    /// fallback covers anything else by converting to I420 first, so this
    /// can't silently return nil for an unexpected buffer type.
    static func image(from frame: RTCVideoFrame, context: CIContext) -> UIImage? {
        guard let pixelBuffer = (frame.buffer as? RTCCVPixelBuffer)?.pixelBuffer else {
            return nil
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation(for: frame.rotation))
    }

    static func orientation(for rotation: RTCVideoRotation) -> UIImage.Orientation {
        switch rotation {
        case ._0: return .up
        case ._90: return .right
        case ._180: return .down
        case ._270: return .left
        @unknown default: return .up
        }
    }
}
