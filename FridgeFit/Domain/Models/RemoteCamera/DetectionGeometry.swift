//
//  DetectionGeometry.swift
//  FridgeFit
//

import CoreGraphics
import Foundation

/// Maps Vision's normalised boxes onto what `RTCMTLVideoView` is actually
/// showing.
///
/// Three coordinate systems have to be reconciled, and getting any one of
/// them wrong produces boxes that look plausible but sit in the wrong place:
///
/// 1. **Vision** returns boxes normalised to the *oriented* image, with the
///    origin at the **bottom-left** and y increasing upwards.
/// 2. **SwiftUI** has the origin at the **top-left** with y increasing
///    downwards.
/// 3. **`.scaleAspectFill`** scales the video to cover the view and centres
///    it, cropping whatever overflows. So the video is generally *larger*
///    than the view and partly off-screen.
///
/// Scaling a normalised rect straight onto the view's bounds - the obvious
/// thing to do - is wrong whenever the video and the view have different
/// aspect ratios, which is almost always.
///
/// Rotation is handled before this point: the frame's rotation is given to
/// Vision as a `CGImagePropertyOrientation`, so the boxes that arrive here
/// are already in upright, display-oriented space. `sourceSize` is the size
/// after that rotation.
nonisolated enum DetectionGeometry {

    /// Converts one normalised Vision box into view coordinates.
    ///
    /// - Parameters:
    ///   - boundingBox: normalised, Vision orientation (bottom-left origin).
    ///   - sourceSize: the oriented frame size, in pixels.
    ///   - viewSize: the size of the view the video is drawn into.
    ///   - contentMode: how the video is fitted. `.scaleAspectFill` matches
    ///     `WebRTCVideoView`.
    /// - Returns: a rect in the view's coordinate space, or `nil` if the
    ///   geometry is degenerate or the box lies entirely outside the visible
    ///   (cropped) region.
    static func rect(
        for boundingBox: CGRect,
        sourceSize: CGSize,
        viewSize: CGSize,
        contentMode: VideoContentMode = .scaleAspectFill
    ) -> CGRect? {
        guard
            sourceSize.width > 0, sourceSize.height > 0,
            viewSize.width > 0, viewSize.height > 0,
            boundingBox.width > 0, boundingBox.height > 0
        else {
            return nil
        }

        let scale: CGFloat
        switch contentMode {
        case .scaleAspectFill:
            // Cover the view; the overflow is cropped.
            scale = max(viewSize.width / sourceSize.width, viewSize.height / sourceSize.height)
        case .scaleAspectFit:
            // Fit inside the view; the remainder is letterboxed.
            scale = min(viewSize.width / sourceSize.width, viewSize.height / sourceSize.height)
        }

        let displayed = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        // Centred, so for aspect-fill these are negative - the video starts
        // off the top/left edge of the view.
        let originX = (viewSize.width - displayed.width) / 2
        let originY = (viewSize.height - displayed.height) / 2

        // Flip the y axis: Vision's bottom-left origin to SwiftUI's top-left.
        // `maxY` rather than `minY` because flipping turns the box's top edge
        // into its bottom edge.
        let flippedY = 1 - boundingBox.maxY

        let rect = CGRect(
            x: originX + boundingBox.minX * displayed.width,
            y: originY + flippedY * displayed.height,
            width: boundingBox.width * displayed.width,
            height: boundingBox.height * displayed.height
        )

        // An object sitting in the cropped-away region shouldn't be drawn
        // floating outside the video.
        guard rect.intersects(CGRect(origin: .zero, size: viewSize)) else { return nil }
        return rect
    }

    /// Clamps a rect to the visible area, so a box straddling the crop edge
    /// is drawn up to the edge instead of spilling outside the video.
    static func clamped(_ rect: CGRect, to viewSize: CGSize) -> CGRect {
        rect.intersection(CGRect(origin: .zero, size: viewSize))
    }

    /// How the video is fitted into its view.
    nonisolated enum VideoContentMode: Sendable {
        /// What `WebRTCVideoView` uses.
        case scaleAspectFill
        case scaleAspectFit
    }
}

// MARK: - Frame orientation

/// Maps WebRTC's frame rotation onto the orientation Vision needs, and gives
/// the resulting upright frame size.
///
/// `RTCVideoFrame.rotation` says how far the buffer must be rotated to be
/// displayed the right way up - `RTCMTLVideoView` applies it when rendering.
/// Vision is told the same thing via `CGImagePropertyOrientation`, so its
/// output is already in display space and the overlay needs no rotation of
/// its own.
nonisolated enum FrameOrientation {

    /// Rotation in degrees, matching `RTCVideoRotation`'s raw values.
    nonisolated enum Rotation: Int, Sendable, CaseIterable {
        case none = 0
        case ninety = 90
        case oneEighty = 180
        case twoSeventy = 270
    }

    /// The `CGImagePropertyOrientation` raw value for a rotation.
    ///
    /// Returned as the raw value so this stays testable without importing
    /// ImageIO into the test target.
    static func cgOrientationRawValue(for rotation: Rotation) -> UInt32 {
        switch rotation {
        case .none: return 1       // .up
        case .ninety: return 6     // .right
        case .oneEighty: return 3  // .down
        case .twoSeventy: return 8 // .left
        }
    }

    /// The frame size as displayed: width and height swap for a quarter turn.
    static func orientedSize(width: Int, height: Int, rotation: Rotation) -> CGSize {
        switch rotation {
        case .none, .oneEighty:
            return CGSize(width: width, height: height)
        case .ninety, .twoSeventy:
            return CGSize(width: height, height: width)
        }
    }
}
