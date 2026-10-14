//
//  FrameDetecting.swift
//  FridgeFit
//

import CoreGraphics
import CoreVideo
import ImageIO

/// Runs object detection on one decoded video frame.
///
/// `YOLOFoodDetectionService` is the only real conformance. The protocol
/// exists so `RemoteVideoFrameTap` - which owns the throttling, the
/// one-in-flight rule and the cancellation semantics - can be tested with a
/// detector whose timing the test controls, rather than racing against real
/// Core ML inference.
///
/// Implementations are called from a background queue, one call at a time.
nonisolated protocol FrameDetecting: Sendable {
    /// - Parameters:
    ///   - pixelBuffer: the decoded frame, used in place.
    ///   - orientation: rotation to apply so the frame is upright.
    ///   - orientedSize: frame size after that rotation, echoed into the
    ///     result so the overlay maps boxes against the right geometry.
    func detect(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        orientedSize: CGSize
    ) throws -> DetectionFrame
}
