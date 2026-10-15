//
//  YOLODetectionGeometryTests.swift
//  FridgeFitTests
//

import CoreGraphics
import XCTest
@testable import FridgeFit

/// Mapping Vision's normalised boxes onto what the video view is showing.
///
/// This is the part that decides whether boxes land on the objects or
/// somewhere plausible-but-wrong, and it is pure arithmetic, so it gets
/// tested properly rather than eyeballed on a device.
final class YOLODetectionGeometryTests: XCTestCase {

    private func assertRect(
        _ rect: CGRect?,
        _ expected: CGRect,
        accuracy: CGFloat = 0.01,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let rect else {
            return XCTFail("expected a rect, got nil", file: file, line: line)
        }
        XCTAssertEqual(rect.minX, expected.minX, accuracy: accuracy, "minX", file: file, line: line)
        XCTAssertEqual(rect.minY, expected.minY, accuracy: accuracy, "minY", file: file, line: line)
        XCTAssertEqual(rect.width, expected.width, accuracy: accuracy, "width", file: file, line: line)
        XCTAssertEqual(rect.height, expected.height, accuracy: accuracy, "height", file: file, line: line)
    }

    // MARK: - The y-axis flip

    /// Vision's origin is bottom-left; SwiftUI's is top-left. Getting this
    /// wrong mirrors every box vertically - which looks right for a centred
    /// object and badly wrong for anything else.
    func test_theYAxisIsFlippedFromVisionToSwiftUI() {
        // A box hugging the BOTTOM in Vision terms (y near 0)…
        let rect = DetectionGeometry.rect(
            for: CGRect(x: 0, y: 0, width: 0.5, height: 0.25),
            sourceSize: CGSize(width: 100, height: 100),
            viewSize: CGSize(width: 100, height: 100)
        )

        // …must land at the BOTTOM in SwiftUI terms (large y).
        assertRect(rect, CGRect(x: 0, y: 75, width: 50, height: 25))
    }

    func test_aTopEdgeBoxLandsAtTheTop() {
        let rect = DetectionGeometry.rect(
            for: CGRect(x: 0, y: 0.75, width: 0.5, height: 0.25),
            sourceSize: CGSize(width: 100, height: 100),
            viewSize: CGSize(width: 100, height: 100)
        )

        assertRect(rect, CGRect(x: 0, y: 0, width: 50, height: 25))
    }

    func test_aCentredBoxStaysCentred() {
        let rect = DetectionGeometry.rect(
            for: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            sourceSize: CGSize(width: 200, height: 200),
            viewSize: CGSize(width: 200, height: 200)
        )

        assertRect(rect, CGRect(x: 50, y: 50, width: 100, height: 100))
    }

    // MARK: - Aspect-fill cropping

    /// The case that makes naive scaling wrong: portrait video in a wider
    /// view. The video is scaled to cover the width, so it overflows
    /// vertically and the top and bottom are cropped.
    func test_portraitVideoInAWiderViewIsCroppedVerticallyNotSquashed() {
        // 720x1280 video (0.5625 aspect) in a 360x480 view (0.75 aspect).
        // scale = max(360/720, 480/1280) = max(0.5, 0.375) = 0.5
        // displayed = 360 x 640, so 160pt overflows and originY = -80.
        let rect = DetectionGeometry.rect(
            for: CGRect(x: 0, y: 0, width: 1, height: 1),
            sourceSize: CGSize(width: 720, height: 1280),
            viewSize: CGSize(width: 360, height: 480)
        )

        assertRect(rect, CGRect(x: 0, y: -80, width: 360, height: 640))
    }

    /// Landscape video in a taller view: scaled to cover the height, so the
    /// left and right are cropped.
    func test_landscapeVideoInATallerViewIsCroppedHorizontally() {
        // 1280x720 in a 360x480 view.
        // scale = max(360/1280, 480/720) = max(0.28125, 0.6667) = 0.6667
        // displayed = 853.3 x 480, originX = (360 - 853.3)/2 = -246.67
        let rect = DetectionGeometry.rect(
            for: CGRect(x: 0, y: 0, width: 1, height: 1),
            sourceSize: CGSize(width: 1280, height: 720),
            viewSize: CGSize(width: 360, height: 480)
        )

        assertRect(rect, CGRect(x: -246.67, y: 0, width: 853.33, height: 480), accuracy: 0.1)
    }

    /// The whole point of the exercise: a centred object stays centred on
    /// screen even though the video overflows the view.
    func test_aCentredObjectInCroppedVideoLandsInTheViewCentre() {
        let rect = DetectionGeometry.rect(
            for: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            sourceSize: CGSize(width: 720, height: 1280),
            viewSize: CGSize(width: 360, height: 480)
        )

        let centre = CGPoint(x: rect!.midX, y: rect!.midY)
        XCTAssertEqual(centre.x, 180, accuracy: 0.5, "should be horizontally centred")
        XCTAssertEqual(centre.y, 240, accuracy: 0.5, "should be vertically centred")
    }

    /// Scaling the normalised rect straight onto the view - the obvious
    /// wrong implementation - would give a different answer here. This test
    /// exists to pin that difference down.
    func test_aspectFillDiffersFromNaiveStretching() {
        let box = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        let sourceSize = CGSize(width: 720, height: 1280)
        let viewSize = CGSize(width: 360, height: 480)

        let correct = DetectionGeometry.rect(for: box, sourceSize: sourceSize, viewSize: viewSize)!
        let naive = CGRect(
            x: box.minX * viewSize.width,
            y: (1 - box.maxY) * viewSize.height,
            width: box.width * viewSize.width,
            height: box.height * viewSize.height
        )

        XCTAssertNotEqual(correct.height, naive.height, accuracy: 0.001)
        XCTAssertEqual(correct.height, 0.2 * 640, accuracy: 0.01, "scaled by the video, not the view")
        XCTAssertEqual(naive.height, 0.2 * 480, accuracy: 0.01)
    }

    func test_squareVideoInASquareViewNeedsNoCrop() {
        let rect = DetectionGeometry.rect(
            for: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            sourceSize: CGSize(width: 480, height: 480),
            viewSize: CGSize(width: 240, height: 240)
        )

        assertRect(rect, CGRect(x: 60, y: 60, width: 120, height: 120))
    }

    // MARK: - Aspect fit, for completeness

    func test_aspectFitLetterboxesInsteadOfCropping() {
        // 1280x720 fitted into 360x480: scale = min(0.28125, 0.6667) = 0.28125
        // displayed = 360 x 202.5, centred vertically with bars.
        let rect = DetectionGeometry.rect(
            for: CGRect(x: 0, y: 0, width: 1, height: 1),
            sourceSize: CGSize(width: 1280, height: 720),
            viewSize: CGSize(width: 360, height: 480),
            contentMode: .scaleAspectFit
        )

        assertRect(rect, CGRect(x: 0, y: 138.75, width: 360, height: 202.5), accuracy: 0.1)
    }

    // MARK: - Degenerate input

    func test_zeroSizedInputProducesNoRect() {
        let box = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)

        XCTAssertNil(DetectionGeometry.rect(for: box, sourceSize: .zero, viewSize: CGSize(width: 10, height: 10)))
        XCTAssertNil(DetectionGeometry.rect(for: box, sourceSize: CGSize(width: 10, height: 10), viewSize: .zero))
    }

    func test_aZeroAreaBoxProducesNoRect() {
        XCTAssertNil(DetectionGeometry.rect(
            for: CGRect(x: 0.5, y: 0.5, width: 0, height: 0),
            sourceSize: CGSize(width: 100, height: 100),
            viewSize: CGSize(width: 100, height: 100)
        ))
    }

    /// An object in the part of the video that aspect-fill crops away
    /// shouldn't be drawn floating outside the visible frame.
    func test_aBoxEntirelyInTheCroppedRegionIsDropped() {
        // Portrait video in a wide view crops the top and bottom heavily.
        let rect = DetectionGeometry.rect(
            for: CGRect(x: 0.4, y: 0.98, width: 0.1, height: 0.02),
            sourceSize: CGSize(width: 720, height: 4000),
            viewSize: CGSize(width: 360, height: 100)
        )

        XCTAssertNil(rect)
    }

    func test_clampingKeepsABoxInsideTheView() {
        let clamped = DetectionGeometry.clamped(
            CGRect(x: -20, y: -10, width: 100, height: 100),
            to: CGSize(width: 60, height: 60)
        )

        XCTAssertEqual(clamped, CGRect(x: 0, y: 0, width: 60, height: 60))
    }

    // MARK: - Rotation

    func test_rotationMapsToTheVisionOrientation() {
        // Must match CGImagePropertyOrientation's raw values.
        XCTAssertEqual(FrameOrientation.cgOrientationRawValue(for: .none), 1)        // .up
        XCTAssertEqual(FrameOrientation.cgOrientationRawValue(for: .ninety), 6)      // .right
        XCTAssertEqual(FrameOrientation.cgOrientationRawValue(for: .oneEighty), 3)   // .down
        XCTAssertEqual(FrameOrientation.cgOrientationRawValue(for: .twoSeventy), 8)  // .left
    }

    func test_aQuarterTurnSwapsWidthAndHeight() {
        XCTAssertEqual(
            FrameOrientation.orientedSize(width: 1280, height: 720, rotation: .ninety),
            CGSize(width: 720, height: 1280)
        )
        XCTAssertEqual(
            FrameOrientation.orientedSize(width: 1280, height: 720, rotation: .twoSeventy),
            CGSize(width: 720, height: 1280)
        )
    }

    func test_aHalfTurnKeepsTheDimensions() {
        XCTAssertEqual(
            FrameOrientation.orientedSize(width: 1280, height: 720, rotation: .none),
            CGSize(width: 1280, height: 720)
        )
        XCTAssertEqual(
            FrameOrientation.orientedSize(width: 1280, height: 720, rotation: .oneEighty),
            CGSize(width: 1280, height: 720)
        )
    }

    /// A landscape sensor frame rotated 90° is displayed portrait, and the
    /// overlay geometry has to use the portrait size or every box is stretched
    /// along the wrong axis.
    func test_aRotatedFrameIsMappedAgainstItsDisplayedSize() {
        let sensorWidth = 1280
        let sensorHeight = 720
        let oriented = FrameOrientation.orientedSize(
            width: sensorWidth, height: sensorHeight, rotation: .ninety
        )
        let viewSize = CGSize(width: 360, height: 640)

        let rect = DetectionGeometry.rect(
            for: CGRect(x: 0, y: 0, width: 1, height: 1),
            sourceSize: oriented,
            viewSize: viewSize
        )!

        // 720x1280 into 360x640 is an exact fit - no crop, no letterbox.
        assertRect(rect, CGRect(x: 0, y: 0, width: 360, height: 640))
    }

    func test_everyRotationHasAnOrientation() {
        for rotation in FrameOrientation.Rotation.allCases {
            let raw = FrameOrientation.cgOrientationRawValue(for: rotation)
            XCTAssertTrue((1...8).contains(raw), "\(rotation) -> \(raw)")
        }
    }
}
