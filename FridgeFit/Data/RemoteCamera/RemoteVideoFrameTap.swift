//
//  RemoteVideoFrameTap.swift
//  FridgeFit
//

import CoreVideo
import Foundation
import ImageIO
import OSLog
@preconcurrency import WebRTC

/// Taps decoded frames off the remote video track and feeds them to YOLO.
///
/// Attached to the `RTCVideoTrack` as a second `RTCVideoRenderer`, alongside
/// the `RTCMTLVideoView` that actually draws the video - the same trick
/// `FirstFrameSentinel` uses. The video pipeline is untouched: this reads the
/// frames WebRTC has already decoded and never feeds anything back.
///
/// Deliberately *not* a screenshot of the SwiftUI view. Rendering the view to
/// an image would capture the cropped, scaled, composited result at whatever
/// the screen refresh happens to be, and would put a full readback on the
/// main thread every time.
///
/// ## Keeping the video smooth
///
/// `renderFrame` is called on a WebRTC decoder thread at the stream's full
/// rate, and anything slow in there stalls playback. So this method does
/// almost nothing: two cheap checks under a lock, and either drop the frame
/// or hand it to a background queue. Inference itself never happens here.
///
/// The rules, in order:
/// - **Throttle.** Frames arriving sooner than `minimumInterval` after the
///   last *started* inference are dropped. At 3 FPS against a 30 FPS stream
///   that is nine frames in ten.
/// - **One in flight.** If an inference is still running, drop. There is no
///   queue, so a slow device falls behind on detections rather than building
///   an unbounded backlog of stale frames.
/// - **Newest wins.** Because dropped frames are discarded rather than
///   buffered, whatever gets through is always the most recent frame.
nonisolated final class RemoteVideoFrameTap: NSObject, RTCVideoRenderer, @unchecked Sendable {

    /// ~3 FPS. Comfortably ahead of a human noticing lag, and far enough
    /// below the video rate to leave the decoder alone.
    static let defaultMinimumInterval: TimeInterval = 1.0 / 3.0

    private let detector: any FrameDetecting
    private let minimumInterval: TimeInterval
    private let onResult: @MainActor (DetectionFrame) -> Void
    private let onFailure: @MainActor (YOLODetectionError) -> Void
    private let now: @Sendable () -> TimeInterval
    private let logger = Logger(subsystem: "com.Fridge.FridgeFit", category: "YOLOTap")

    /// Serial, utility QoS: detection is explicitly lower priority than
    /// playback. One queue also reinforces the one-in-flight rule.
    private let inferenceQueue = DispatchQueue(
        label: "com.Fridge.FridgeFit.yolo.inference",
        qos: .utility
    )

    private let lock = NSLock()
    private var isEnabled = true
    private var isCancelled = false
    private var isInferring = false
    private var lastStartedAt: TimeInterval = -.greatestFiniteMagnitude
    /// Set once a terminal error is reported, so it isn't reported again for
    /// every subsequent frame.
    private var hasReportedTerminalFailure = false

    private(set) var processedFrameCount = 0
    private(set) var droppedFrameCount = 0

    init(
        detector: any FrameDetecting,
        minimumInterval: TimeInterval = RemoteVideoFrameTap.defaultMinimumInterval,
        now: @escaping @Sendable () -> TimeInterval = { CACurrentMediaTime() },
        onResult: @escaping @MainActor (DetectionFrame) -> Void,
        onFailure: @escaping @MainActor (YOLODetectionError) -> Void
    ) {
        self.detector = detector
        self.minimumInterval = minimumInterval
        self.now = now
        self.onResult = onResult
        self.onFailure = onFailure
        super.init()
    }

    // MARK: - Control

    /// Pauses or resumes sampling without detaching.
    ///
    /// Used by the toggle: the renderer stays attached to the track, frames
    /// keep arriving and are dropped immediately, and video is unaffected.
    func setEnabled(_ enabled: Bool) {
        lock.lock()
        isEnabled = enabled
        lock.unlock()
    }

    /// Permanently stops this tap.
    ///
    /// Any inference already running finishes - Vision has no cancellation
    /// point mid-request - but its result is discarded rather than delivered.
    /// That is what stops boxes from a previous session appearing over a new
    /// one after a reconnect or a camera switch.
    func cancel() {
        lock.lock()
        isCancelled = true
        isEnabled = false
        lock.unlock()
    }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isCancelled && isEnabled
    }

    /// Whether an inference is currently running.
    ///
    /// Exposed because "has the detector been called" and "has it finished"
    /// are different moments, and a caller that acts on the first while the
    /// second is still pending gets its next frame dropped by the
    /// one-in-flight rule.
    var isBusy: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isInferring
    }

    var statistics: (processed: Int, dropped: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (processedFrameCount, droppedFrameCount)
    }

    // MARK: - RTCVideoRenderer

    func setSize(_ size: CGSize) {}

    /// Called on a WebRTC decoder thread. Must stay cheap.
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }

        let timestamp = now()
        lock.lock()
        let shouldProcess = !isCancelled
            && isEnabled
            && !isInferring
            && !hasReportedTerminalFailure
            && (timestamp - lastStartedAt) >= minimumInterval
        if shouldProcess {
            isInferring = true
            lastStartedAt = timestamp
            processedFrameCount += 1
        } else {
            droppedFrameCount += 1
        }
        lock.unlock()

        guard shouldProcess else { return }

        // The frame is retained by this closure until inference finishes, so
        // WebRTC can't recycle the underlying buffer out from under Vision.
        inferenceQueue.async { [weak self] in
            self?.runInference(on: frame)
        }
    }

    // MARK: - Inference, on the background queue

    private func runInference(on frame: RTCVideoFrame) {
        defer {
            lock.lock()
            isInferring = false
            lock.unlock()
        }

        // Bail before doing any work if the session went away while this was
        // queued.
        lock.lock()
        let cancelled = isCancelled
        lock.unlock()
        guard !cancelled else { return }

        guard let pixelBuffer = (frame.buffer as? RTCCVPixelBuffer)?.pixelBuffer else {
            // Software-decoded video (VP8/VP9) arrives as an I420 buffer
            // rather than a CVPixelBuffer. Converting it is possible but
            // would mean a per-frame colour-space conversion on the CPU; for
            // two iPhones H.264 is negotiated and this path doesn't occur.
            // Reported rather than silently producing nothing.
            report(.unsupportedPixelFormat)
            return
        }

        let rotation = Self.rotation(for: frame.rotation)
        let orientation = CGImagePropertyOrientation(
            rawValue: FrameOrientation.cgOrientationRawValue(for: rotation)
        ) ?? .up
        let orientedSize = FrameOrientation.orientedSize(
            width: Int(frame.width),
            height: Int(frame.height),
            rotation: rotation
        )

        do {
            let result = try detector.detect(
                in: pixelBuffer,
                orientation: orientation,
                orientedSize: orientedSize
            )

            // Re-check: the session may have ended while Vision was running.
            // Delivering now would paint boxes over a disconnected view.
            lock.lock()
            let stillWanted = !isCancelled && isEnabled
            lock.unlock()
            guard stillWanted else { return }

            let deliver = onResult
            Task { @MainActor in deliver(result) }
        } catch let error as YOLODetectionError {
            report(error)
        } catch {
            report(.inferenceFailed(reason: error.localizedDescription))
        }
    }

    private func report(_ error: YOLODetectionError) {
        lock.lock()
        let alreadyReported = hasReportedTerminalFailure
        if !error.isRecoverable {
            hasReportedTerminalFailure = true
        }
        let cancelled = isCancelled
        lock.unlock()

        guard !cancelled, !alreadyReported else { return }
        logger.error("Detection failed: \(String(describing: error), privacy: .public)")

        let deliver = onFailure
        Task { @MainActor in deliver(error) }
    }

    /// `RTCVideoRotation` to our WebRTC-free rotation type.
    static func rotation(for rtcRotation: RTCVideoRotation) -> FrameOrientation.Rotation {
        FrameOrientation.Rotation(rawValue: rtcRotation.rawValue) ?? .none
    }
}
