//
//  IngredientNormalizerTests.swift
//  FridgeFitTests
//

import CoreGraphics
import XCTest
@testable import FridgeFit

/// Stage 2 of the policy layer: what the app is willing to *consider*.
///
/// What it is willing to *draw* is `DetectionDisplayFilterTests`. The split
/// matters - the normaliser's floor is `candidateThreshold`, deliberately
/// lower than the overlay's, so the snapshot pipeline can still corroborate a
/// box the Controller withholds.
///
/// Measured precision of the ingredient model is around 56% at the display
/// floor, so these rules are what stand between a confident-sounding label and
/// the user. They are pure functions, and tested as such.
final class IngredientNormalizerTests: XCTestCase {

    private func taxonomy() throws -> IngredientTaxonomy {
        try IngredientTaxonomy.load(in: .main)
    }

    private func normalizer(
        candidate: Float = 0.30,
        strong: Float = 0.60,
        duplicateIoU: CGFloat = 0.55,
        maximum: Int = 24
    ) throws -> IngredientNormalizer {
        var policy = DetectionFilterPolicy.default
        policy.candidateThreshold = candidate
        policy.strongThreshold = strong
        policy.duplicateIoU = duplicateIoU
        policy.maximumCandidates = maximum
        return IngredientNormalizer(taxonomy: try taxonomy(), policy: policy)
    }

    private func frame(_ objects: [(String, Float, CGRect)]) -> DetectionFrame {
        DetectionFrame(
            objects: objects.map {
                DetectedObject(label: $0.0, confidence: $0.1, boundingBox: $0.2)
            },
            sourceSize: CGSize(width: 640, height: 480)
        )
    }

    private let box = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    private func box(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 0.2) -> CGRect {
        CGRect(x: x, y: y, width: size, height: size)
    }

    // MARK: - Confidence filtering

    func test_detectionsBelowTheCandidateThresholdAreDropped() throws {
        let result = try normalizer().normalize(
            frame([("apple", 0.29, box)]), source: .ingredientDetector
        )

        XCTAssertTrue(result.isEmpty, "0.29 is below the 0.30 candidate floor")
    }

    func test_theCandidateThresholdIsInclusive() throws {
        let result = try normalizer().normalize(
            frame([("apple", 0.30, box)]), source: .ingredientDetector
        )

        XCTAssertEqual(result.ingredients.count, 1)
    }

    /// The whole reason stage 2 exists. A 0.34 apple is below the overlay's
    /// 0.40 floor and must still become a candidate, because the snapshot
    /// pipeline runs region classification over candidates - and a second
    /// method agreeing is exactly how a weak box earns its place.
    func test_candidatesBelowTheDisplayThresholdSurviveNormalisation() throws {
        let policy = DetectionFilterPolicy.default
        let result = try normalizer().normalize(
            frame([("apple", 0.34, box)]), source: .ingredientDetector
        )

        XCTAssertLessThan(0.34, policy.displayThreshold)
        XCTAssertEqual(result.ingredients.count, 1,
                       "a sub-display candidate must still reach fusion")
    }

    func test_detectionsBelowTheStrongThresholdAreFlaggedForReview() throws {
        let result = try normalizer().normalize(
            frame([("apple", 0.50, box)]), source: .ingredientDetector
        )

        let apple = try XCTUnwrap(result.ingredients.first)
        XCTAssertEqual(apple.reviewReason, .lowConfidence)
        XCTAssertTrue(apple.hasReviewFlag)
        XCTAssertEqual(apple.band, .tentative)
        XCTAssertEqual(result.reviewCount, 1)
    }

    func test_confidentDetectionsCarryNoFlagButAreStillNotVerified() throws {
        let result = try normalizer().normalize(
            frame([("apple", 0.85, box)]), source: .ingredientDetector
        )

        let apple = try XCTUnwrap(result.ingredients.first)
        XCTAssertNil(apple.reviewReason)
        XCTAssertFalse(apple.hasReviewFlag)
        XCTAssertEqual(apple.band, .strong, "0.85 is in the strong band")
        // The band changes how it is drawn, never whether it is believed. The
        // most confident detection on the evaluation set is wrong.
        XCTAssertFalse(apple.isVerified)
        XCTAssertTrue(apple.requiresConfirmation)
    }

    func test_theCandidateThresholdIsConfigurable() throws {
        let permissive = try normalizer(candidate: 0.20)
        let strict = try normalizer(candidate: 0.80)
        let detections = frame([("apple", 0.50, box)])

        XCTAssertEqual(permissive.normalize(detections, source: .ingredientDetector).ingredients.count, 1)
        XCTAssertTrue(strict.normalize(detections, source: .ingredientDetector).isEmpty)
    }

    // MARK: - Decoys

    /// Decoys exist so non-food objects have somewhere to go. They are never
    /// results.
    func test_decoyTermsAreNeverReportedAsIngredients() throws {
        let result = try normalizer().normalize(
            frame([
                ("plate", 0.95, box(0.1, 0.1)),
                ("person", 0.92, box(0.4, 0.1)),
                ("kitchen knife", 0.88, box(0.7, 0.1)),
                ("apple", 0.70, box(0.1, 0.5)),
            ]),
            source: .ingredientDetector
        )

        XCTAssertEqual(result.ingredients.map(\.ingredientId), ["apple"])
        XCTAssertFalse(result.categories.contains(.decoy))
    }

    func test_unknownTermsAreIgnored() throws {
        let result = try normalizer().normalize(
            frame([("unobtainium", 0.99, box)]), source: .ingredientDetector
        )

        XCTAssertTrue(result.isEmpty, "a term outside the taxonomy must not be invented into an ingredient")
    }

    // MARK: - Ambiguous classes

    /// The brief is explicit: do not treat uncertain raw meat as a specific
    /// species.
    func test_ambiguousMeatIsReportedGenericallyAndFlagged() throws {
        let result = try normalizer().normalize(
            frame([("raw beef steak", 0.92, box)]), source: .ingredientDetector
        )

        let meat = try XCTUnwrap(result.ingredients.first)
        XCTAssertEqual(meat.ingredientId, "red_meat", "must not assert beef specifically")
        XCTAssertEqual(meat.displayName, "Red Meat")
        XCTAssertEqual(meat.reviewReason, .ambiguousClass)
        // The raw term is preserved so a reviewer can see what the model said.
        XCTAssertEqual(meat.rawTerm, "raw beef steak")
    }

    /// High confidence does not make an indistinguishable class distinguishable.
    func test_ambiguousClassesStayFlaggedEvenAtHighConfidence() throws {
        let result = try normalizer().normalize(
            frame([("lamb chop", 0.99, box)]), source: .ingredientDetector
        )

        XCTAssertEqual(result.ingredients.first?.reviewReason, .ambiguousClass)
        XCTAssertEqual(result.ingredients.first?.ingredientId, "red_meat")
    }

    func test_differentAmbiguousTermsCollapseToTheSameIngredient() throws {
        let result = try normalizer().normalize(
            frame([
                ("raw beef steak", 0.80, box(0.1, 0.1)),
                ("raw pork", 0.75, box(0.5, 0.5)),
            ]),
            source: .ingredientDetector
        )

        XCTAssertEqual(Set(result.ingredients.map(\.ingredientId)), ["red_meat"])
        XCTAssertEqual(result.ingredients.count, 2, "distinct objects stay distinct")
    }

    func test_unambiguousMeatIsNotGenericised() throws {
        let result = try normalizer().normalize(
            frame([("bacon", 0.90, box)]), source: .ingredientDetector
        )

        XCTAssertEqual(result.ingredients.first?.ingredientId, "bacon")
        XCTAssertNil(result.ingredients.first?.reviewReason)
    }

    // MARK: - Duplicate suppression

    /// Two vocabulary terms mapping to one ingredient survive the model's own
    /// per-class NMS and would otherwise draw two boxes on one object.
    func test_overlappingBoxesOfTheSameIngredientAreSuppressed() throws {
        let result = try normalizer().normalize(
            frame([
                ("raw beef steak", 0.80, CGRect(x: 0.10, y: 0.10, width: 0.30, height: 0.30)),
                ("minced beef", 0.70, CGRect(x: 0.12, y: 0.12, width: 0.30, height: 0.30)),
            ]),
            source: .ingredientDetector
        )

        XCTAssertEqual(result.ingredients.count, 1, "one object should produce one box")
        XCTAssertEqual(result.ingredients.first?.confidence, 0.80, "the best one survives")
    }

    /// Different ingredients overlapping are two real things - a tomato on a
    /// lettuce leaf - and must both survive.
    func test_overlappingBoxesOfDifferentIngredientsAreKept() throws {
        let result = try normalizer().normalize(
            frame([
                ("tomato", 0.80, CGRect(x: 0.10, y: 0.10, width: 0.30, height: 0.30)),
                ("lettuce", 0.70, CGRect(x: 0.12, y: 0.12, width: 0.30, height: 0.30)),
            ]),
            source: .ingredientDetector
        )

        XCTAssertEqual(Set(result.ingredients.map(\.ingredientId)), ["tomato", "lettuce"])
    }

    func test_distantBoxesOfTheSameIngredientAreKept() throws {
        let result = try normalizer().normalize(
            frame([
                ("apple", 0.80, box(0.05, 0.05)),
                ("apple", 0.75, box(0.70, 0.70)),
            ]),
            source: .ingredientDetector
        )

        XCTAssertEqual(result.ingredients.count, 2, "two apples are two apples")
    }

    func test_theOverlapThresholdIsConfigurable() throws {
        let detections = frame([
            ("apple", 0.80, CGRect(x: 0.10, y: 0.10, width: 0.30, height: 0.30)),
            ("apple", 0.70, CGRect(x: 0.20, y: 0.20, width: 0.30, height: 0.30)),
        ])

        // Intersection 0.2 x 0.2 = 0.04, union 0.09 + 0.09 - 0.04 = 0.14,
        // so IoU is 0.04 / 0.14 = 0.286. A threshold either side of that
        // must flip the outcome.
        XCTAssertEqual(IngredientNormalizer.intersectionOverUnion(
            detections.objects[0].boundingBox, detections.objects[1].boundingBox
        ), 0.286, accuracy: 0.005)

        XCTAssertEqual(try normalizer(duplicateIoU: 0.25).normalize(detections, source: .ingredientDetector).ingredients.count, 1)
        XCTAssertEqual(try normalizer(duplicateIoU: 0.35).normalize(detections, source: .ingredientDetector).ingredients.count, 2)
    }

    func test_intersectionOverUnionIsCorrect() {
        let a = CGRect(x: 0, y: 0, width: 1, height: 1)
        XCTAssertEqual(IngredientNormalizer.intersectionOverUnion(a, a), 1.0, accuracy: 0.001)

        let half = CGRect(x: 0.5, y: 0, width: 1, height: 1)
        // intersection 0.5, union 1.5
        XCTAssertEqual(IngredientNormalizer.intersectionOverUnion(a, half), 1.0 / 3.0, accuracy: 0.001)

        let disjoint = CGRect(x: 5, y: 5, width: 1, height: 1)
        XCTAssertEqual(IngredientNormalizer.intersectionOverUnion(a, disjoint), 0)
    }

    // MARK: - Ordering and caps

    func test_resultsAreSortedByConfidence() throws {
        let result = try normalizer().normalize(
            frame([
                ("apple", 0.55, box(0.1, 0.1)),
                ("banana", 0.90, box(0.4, 0.1)),
                ("carrot", 0.70, box(0.7, 0.1)),
            ]),
            source: .ingredientDetector
        )

        XCTAssertEqual(result.ingredients.map(\.ingredientId), ["banana", "carrot", "apple"])
    }

    func test_theNumberOfBoxesIsCapped() throws {
        let many = (0..<20).map { index in
            ("apple", Float(0.9) - Float(index) * 0.01, box(CGFloat(index) * 0.04, 0.1, 0.03))
        }

        let result = try normalizer(maximum: 5).normalize(frame(many), source: .ingredientDetector)

        XCTAssertEqual(result.ingredients.count, 5, "an overlay must not become a wall of rectangles")
    }

    // MARK: - Frame metadata

    func test_geometryAndSourceAreCarriedThrough() throws {
        let result = try normalizer().normalize(
            frame([("apple", 0.90, box)]), source: .cocoFallback
        )

        XCTAssertEqual(result.sourceSize, CGSize(width: 640, height: 480))
        XCTAssertEqual(result.source, .cocoFallback)
        XCTAssertEqual(result.ingredients.first?.source, .cocoFallback)
    }

    func test_categoriesArePresentedWithoutDuplicates() throws {
        let result = try normalizer().normalize(
            frame([
                ("apple", 0.90, box(0.1, 0.1)),
                ("banana", 0.88, box(0.4, 0.1)),
                ("carrot", 0.86, box(0.7, 0.1)),
            ]),
            source: .ingredientDetector
        )

        XCTAssertEqual(result.categories, [.fruit, .vegetable])
    }

    func test_anEmptyFrameNormalisesToNothing() throws {
        let result = try normalizer().normalize(frame([]), source: .ingredientDetector)

        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.reviewCount, 0)
        XCTAssertTrue(result.categories.isEmpty)
    }

    // MARK: - Presentation

    func test_flaggedItemsAreMarkedInTheOverlayLabel() {
        let confident = DetectedIngredient(
            ingredientId: "apple", displayName: "Apple", category: .fruit,
            confidence: 0.91, boundingBox: .zero, source: .ingredientDetector,
            reviewReason: nil, rawTerm: "apple"
        )
        let uncertain = DetectedIngredient(
            ingredientId: "red_meat", displayName: "Red Meat", category: .meat,
            confidence: 0.52, boundingBox: .zero, source: .ingredientDetector,
            reviewReason: .ambiguousClass, rawTerm: "raw beef steak"
        )

        XCTAssertEqual(confident.overlayLabel, "Apple 91%")
        XCTAssertEqual(uncertain.overlayLabel, "Red Meat? 52%",
                       "uncertainty should be visible, not hidden")
    }

    func test_reviewReasonsExplainThemselves() {
        for reason in [ReviewReason.lowConfidence, .ambiguousClass, .notCorroborated] {
            XCTAssertFalse(reason.message.isEmpty, "\(reason) needs a message")
        }
    }

    func test_detectionSourcesAreDistinguishable() {
        XCTAssertNotEqual(DetectionSource.ingredientDetector.shortName,
                          DetectionSource.cocoFallback.shortName)
        XCTAssertEqual(DetectionSource.cocoFallback.shortName, "YOLO11n")
    }
}
