//
//  YOLODetectionOverlayLayoutTests.swift
//  FridgeFitTests
//

import CoreGraphics
import XCTest
@testable import FridgeFit

/// The overlay's layout decisions, tested as arithmetic rather than pixels.
///
/// `YOLODetectionOverlayTests` renders and inspects pixels, which proves boxes
/// land in the right place. This covers the readability rules that pixel tests
/// cannot express cleanly: whether two labels would collide, and whether a
/// label has room above its box.
final class YOLODetectionOverlayLayoutTests: XCTestCase {

    private let viewSize = CGSize(width: 360, height: 480)

    private func ingredient(
        _ ingredientId: String,
        _ rect: CGRect,
        confidence: Float = 0.80,
        reason: ReviewReason? = nil
    ) -> DetectedIngredient {
        DetectedIngredient(
            ingredientId: ingredientId,
            displayName: ingredientId.capitalized,
            category: .fruit,
            confidence: confidence,
            boundingBox: rect,
            source: .ingredientDetector,
            reviewReason: reason,
            rawTerm: ingredientId,
            band: DetectionFilterPolicy.default.band(for: confidence)
        )
    }

    private func placed(_ ingredients: [DetectedIngredient]) -> [YOLODetectionOverlay.PlacedBox] {
        YOLODetectionOverlay.placedBoxes(
            for: IngredientDetectionFrame(
                ingredients: ingredients,
                // Square source into a 3:4 view, so the aspect-fill crop is
                // actually exercised rather than being a no-op.
                sourceSize: CGSize(width: 480, height: 480),
                source: .ingredientDetector
            ),
            viewSize: viewSize,
            contentMode: .scaleAspectFill
        )
    }

    // MARK: - Label collisions

    /// Two boxes at the same height put their captions in the same place, so
    /// the second one moves inside its own box. Overlapping captions are both
    /// unreadable and ambiguous about which box they name.
    func test_labelsInTheSameRowDoNotBothSitAboveTheirBox() {
        let boxes = placed([
            ingredient("apple", CGRect(x: 0.10, y: 0.40, width: 0.15, height: 0.15), confidence: 0.90),
            ingredient("pear", CGRect(x: 0.16, y: 0.40, width: 0.15, height: 0.15), confidence: 0.70),
        ])

        XCTAssertEqual(boxes.count, 2)
        XCTAssertFalse(boxes[0].labelBelow, "the more confident box keeps the roomier position")
        XCTAssertTrue(boxes[1].labelBelow, "the second label moves inside its box")
    }

    /// Far apart horizontally is not a collision, even at the same height.
    func test_labelsFarApartHorizontallyBothStayAboveTheirBox() {
        let boxes = placed([
            ingredient("apple", CGRect(x: 0.02, y: 0.40, width: 0.12, height: 0.12), confidence: 0.90),
            ingredient("pear", CGRect(x: 0.80, y: 0.40, width: 0.12, height: 0.12), confidence: 0.70),
        ])

        XCTAssertEqual(boxes.count, 2)
        XCTAssertFalse(boxes[0].labelBelow)
        XCTAssertFalse(boxes[1].labelBelow)
    }

    func test_labelsAtDifferentHeightsBothStayAboveTheirBox() {
        let boxes = placed([
            ingredient("apple", CGRect(x: 0.10, y: 0.15, width: 0.15, height: 0.15), confidence: 0.90),
            ingredient("pear", CGRect(x: 0.10, y: 0.55, width: 0.15, height: 0.15), confidence: 0.70),
        ])

        XCTAssertFalse(boxes[0].labelBelow)
        XCTAssertFalse(boxes[1].labelBelow)
    }

    /// A box flush against the top of the view has nowhere to put a caption
    /// above it, so it goes inside regardless of collisions.
    func test_aBoxAtTheTopOfTheViewPutsItsLabelInside() {
        // Vision boxes are bottom-left origin, so y near 1.0 is the top.
        let boxes = placed([
            ingredient("apple", CGRect(x: 0.10, y: 0.97, width: 0.15, height: 0.03))
        ])

        XCTAssertEqual(boxes.count, 1)
        XCTAssertTrue(boxes[0].labelBelow)
    }

    // MARK: - Mapping

    func test_boxesAreClampedToTheView() {
        let boxes = placed([
            ingredient("apple", CGRect(x: -0.2, y: -0.2, width: 0.5, height: 0.5))
        ])

        let rect = try? XCTUnwrap(boxes.first?.rect)
        XCTAssertNotNil(rect)
        XCTAssertGreaterThanOrEqual(rect!.minX, 0)
        XCTAssertGreaterThanOrEqual(rect!.minY, 0)
        XCTAssertLessThanOrEqual(rect!.maxX, viewSize.width + 0.01)
        XCTAssertLessThanOrEqual(rect!.maxY, viewSize.height + 0.01)
    }

    /// A frame with no geometry cannot be mapped, so nothing is placed rather
    /// than something being placed at a guessed position.
    func test_aFrameWithNoSourceSizePlacesNothing() {
        let boxes = YOLODetectionOverlay.placedBoxes(
            for: IngredientDetectionFrame(
                ingredients: [ingredient("apple", CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))],
                sourceSize: .zero,
                source: .ingredientDetector
            ),
            viewSize: viewSize,
            contentMode: .scaleAspectFill
        )

        XCTAssertTrue(boxes.isEmpty)
    }

    func test_anEmptyFramePlacesNothing() {
        XCTAssertTrue(placed([]).isEmpty, "the empty state is the view's job, not a zero-size box")
    }

    // MARK: - Presentation

    func test_everyDisplayedBoxCarriesANameAndAConfidencePercentage() {
        let boxes = placed([
            ingredient("apple", CGRect(x: 0.10, y: 0.20, width: 0.15, height: 0.15), confidence: 0.83),
            ingredient("pear", CGRect(x: 0.60, y: 0.60, width: 0.15, height: 0.15),
                        confidence: 0.47, reason: .lowConfidence),
        ])

        XCTAssertEqual(boxes.map(\.ingredient.overlayLabel), ["Apple 83%", "Pear? 47%"])
    }

    /// Dashing is driven by the band, so uncertainty survives a screenshot.
    func test_tentativeAndFlaggedBoxesAreDashedAndStrongOnesAreNot() {
        let strong = ingredient("apple", .zero, confidence: 0.85)
        let tentative = ingredient("pear", .zero, confidence: 0.45)
        let flaggedButConfident = ingredient("red_meat", .zero, confidence: 0.92,
                                             reason: .ambiguousClass)

        XCTAssertFalse(strong.band.isDashed)
        XCTAssertTrue(tentative.band.isDashed)
        // Confident but ambiguous: the flag has to win, because confidence
        // does not make an indistinguishable class distinguishable.
        XCTAssertFalse(flaggedButConfident.band.isDashed)
        XCTAssertTrue(flaggedButConfident.hasReviewFlag)
    }
}
