//
//  SyntheticVideoSource.swift
//  FridgeFitTests
//

import CoreVideo
import Foundation
@preconcurrency import WebRTC
@testable import FridgeFit

/// A WebRTC video track fed by generated frames instead of a camera.
///
/// The Simulator has no capture device, so `CameraVideoSource` can't run
/// there. This produces a real `RTCVideoTrack` carrying real frames, which
/// is what lets `WebRTCLoopbackTests` exercise the actual encode → RTP →
/// decode path on a machine with no camera.
///
/// The pattern moves between frames on purpose: a static image compresses to
/// almost nothing and can leave the encoder sending only its first keyframe,
/// which would make a broken pipeline look like a working one.
@MainActor
final class SyntheticVideoSource {
    let videoTrack: RTCVideoTrack

    private let videoSource: RTCVideoSource
    private let capturer: RTCVideoCapturer
    private let width: Int
    private let height: Int
    private var frameTask: Task<Void, Never>?
    private var frameIndex = 0

    init(width: Int = 320, height: Int = 240, trackId: String = "synthetic-video") {
        self.width = width
        self.height = height
        videoSource = WebRTCFactory.shared.peerConnectionFactory.videoSource()
        videoSource.adaptOutputFormat(toWidth: Int32(width), height: Int32(height), fps: 15)
        capturer = RTCVideoCapturer(delegate: videoSource)
        videoTrack = WebRTCFactory.shared.peerConnectionFactory.videoTrack(
            with: videoSource,
            trackId: trackId
        )
    }

    /// Starts pushing frames at roughly 15fps.
    func start() {
        guard frameTask == nil else { return }
        frameTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.pushFrame()
                try? await Task.sleep(for: .milliseconds(66))
            }
        }
    }

    func stop() {
        frameTask?.cancel()
        frameTask = nil
    }

    private func pushFrame() {
        guard let pixelBuffer = makePixelBuffer(tick: frameIndex) else { return }
        let frame = RTCVideoFrame(
            buffer: RTCCVPixelBuffer(pixelBuffer: pixelBuffer),
            rotation: ._0,
            timeStampNs: Int64(frameIndex) * 66_000_000
        )
        videoSource.capturer(capturer, didCapture: frame)
        frameIndex += 1
    }

    /// An NV12 buffer with a moving diagonal gradient.
    private func makePixelBuffer(tick: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        if let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) {
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            let plane = luma.assumingMemoryBound(to: UInt8.self)
            for row in 0..<height {
                for column in 0..<width {
                    plane[row * bytesPerRow + column] = UInt8((row + column + tick * 4) % 256)
                }
            }
        }
        // Flat mid-grey chroma - colour isn't what's being verified.
        if let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) {
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
            let plane = chroma.assumingMemoryBound(to: UInt8.self)
            for row in 0..<(height / 2) {
                for column in 0..<width {
                    plane[row * bytesPerRow + column] = 128
                }
            }
        }
        return buffer
    }
}
