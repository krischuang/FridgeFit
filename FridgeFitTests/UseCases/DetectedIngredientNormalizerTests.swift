//
//  DetectedIngredientNormalizerTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class DetectedIngredientNormalizerTests: XCTestCase {
    private let normalizer = DetectedIngredientNormalizer()

    private func raw(
        name: String,
        category: String = "Produce",
        visibleCount: Int = 0,
        confidence: String = "high"
    ) -> RawDetectedIngredient {
        RawDetectedIngredient(name: name, category: category, visibleCount: visibleCount, confidence: confidence)
    }

    func test_normalizer_mapsKnownCategoryAndConfidence() {
        let result = IngredientDetectionResult(ingredients: [
            raw(name: "milk", category: "Dairy", visibleCount: 2, confidence: "medium")
        ])

        let detections = normalizer.normalize(result)

        XCTAssertEqual(detections.count, 1)
        XCTAssertEqual(detections.first?.name, "Milk")
        XCTAssertEqual(detections.first?.category, .dairy)
        XCTAssertEqual(detections.first?.visibleCount, 2)
        XCTAssertEqual(detections.first?.confidence, .medium)
        XCTAssertFalse(detections.first?.isAlreadyInPantry ?? true)
    }

    func test_normalizer_fallsBackToOtherCategory_forUnknownCategory() {
        let detections = normalizer.normalize(
            IngredientDetectionResult(ingredients: [raw(name: "kimchi", category: "fermented-mystery")])
        )

        XCTAssertEqual(detections.first?.category, .other)
    }

    /// An unreadable confidence is not a confident detection.
    func test_normalizer_fallsBackToLowConfidence_forUnknownConfidence() {
        let detections = normalizer.normalize(
            IngredientDetectionResult(ingredients: [raw(name: "tofu", confidence: "extremely sure")])
        )

        XCTAssertEqual(detections.first?.confidence, .low)
    }

    func test_normalizer_treatsZeroVisibleCountAsUnknown() {
        let detections = normalizer.normalize(
            IngredientDetectionResult(ingredients: [raw(name: "chicken", visibleCount: 0)])
        )

        XCTAssertNil(detections.first?.visibleCount)
    }

    func test_normalizer_clampsAbsurdVisibleCount() {
        let detections = normalizer.normalize(
            IngredientDetectionResult(ingredients: [raw(name: "egg", visibleCount: 9_000)])
        )

        XCTAssertEqual(detections.first?.visibleCount, 50)
    }

    func test_normalizer_dropsNegativeVisibleCount() {
        let detections = normalizer.normalize(
            IngredientDetectionResult(ingredients: [raw(name: "egg", visibleCount: -3)])
        )

        XCTAssertNil(detections.first?.visibleCount)
    }

    func test_normalizer_dropsBlankAndOverlongNames() {
        let result = IngredientDetectionResult(ingredients: [
            raw(name: "   "),
            raw(name: ""),
            raw(name: String(repeating: "a", count: 41)),
            raw(name: "carrot")
        ])

        let detections = normalizer.normalize(result)

        XCTAssertEqual(detections.map(\.name), ["Carrot"])
    }

    /// Backstop for the prompt rule about containers and shelves.
    func test_normalizer_dropsNonFoodDetections() {
        let result = IngredientDetectionResult(ingredients: [
            raw(name: "shelf"),
            raw(name: "plastic container"),
            raw(name: "bottle"),
            raw(name: "milk")
        ])

        let detections = normalizer.normalize(result)

        XCTAssertEqual(detections.map(\.name), ["Milk"])
    }

    /// "carton" alone is packaging, but "milk carton" still names a food.
    func test_normalizer_keepsFoodNamesThatMentionPackaging() {
        let detections = normalizer.normalize(
            IngredientDetectionResult(ingredients: [raw(name: "milk carton")])
        )

        XCTAssertEqual(detections.map(\.name), ["Milk Carton"])
    }

    func test_normalizer_collapsesWhitespaceAndCapitalisesName() {
        let detections = normalizer.normalize(
            IngredientDetectionResult(ingredients: [raw(name: "  greek   yogurt ")])
        )

        XCTAssertEqual(detections.first?.name, "Greek Yogurt")
    }

    func test_normalizer_collapsesDuplicates_keepingMostConfident() {
        let result = IngredientDetectionResult(ingredients: [
            raw(name: "tomato", visibleCount: 1, confidence: "low"),
            raw(name: "Tomato", visibleCount: 3, confidence: "high"),
            raw(name: "TOMATO", confidence: "medium")
        ])

        let detections = normalizer.normalize(result)

        XCTAssertEqual(detections.count, 1)
        XCTAssertEqual(detections.first?.confidence, .high)
        XCTAssertEqual(detections.first?.visibleCount, 3)
    }

    func test_normalizer_returnsEmpty_forEmptyResult() {
        XCTAssertTrue(normalizer.normalize(.empty).isEmpty)
    }
}
