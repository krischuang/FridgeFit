//
//  DetectionFusionServiceTests.swift
//  FridgeFitTests
//

import CoreGraphics
import Foundation
import XCTest
@testable import FridgeFit

/// The tiering rules, as pure functions.
///
/// No Vision calls here - fusion takes already-computed results, which is
/// what makes it testable everywhere including the simulator.
final class DetectionFusionServiceTests: XCTestCase {

    private let box = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
    private let otherBox = CGRect(x: 0.6, y: 0.6, width: 0.2, height: 0.2)

    private func detection(
        _ ingredient: String,
        _ confidence: Float = 0.80,
        box: CGRect? = nil,
        category: IngredientGroup = .fruit,
        review: ReviewReason? = nil
    ) -> DetectedIngredient {
        DetectedIngredient(
            ingredientId: ingredient, displayName: ingredient.capitalized,
            category: category, confidence: confidence,
            boundingBox: box ?? self.box, source: .ingredientDetector,
            reviewReason: review, rawTerm: ingredient
        )
    }

    private func frame(_ items: [DetectedIngredient]) -> IngredientDetectionFrame {
        IngredientDetectionFrame(
            ingredients: items, sourceSize: CGSize(width: 640, height: 480),
            source: .ingredientDetector
        )
    }

    private func classified(
        _ ingredient: String,
        _ confidence: Float = 0.70,
        category: IngredientGroup = .fruit,
        review: Bool = false
    ) -> ClassificationResult {
        ClassificationResult(
            ingredients: [ClassifiedIngredient(
                ingredientId: ingredient, displayName: ingredient.capitalized,
                category: category, confidence: confidence,
                rawIdentifier: ingredient, requiresReview: review
            )],
            rejectedFoodClaims: []
        )
    }

    // MARK: - Tiers

    func test_bothMethodsAgreeingOnARegionIsTheTopTier() {
        let apple = detection("apple")
        let result = DetectionFusionService().fuse(
            detections: frame([apple]),
            regionClassifications: [apple.id: classified("apple")]
        )

        let fused = try! XCTUnwrap(result.localised.first)
        XCTAssertEqual(fused.tier, .agreed)
        XCTAssertEqual(fused.sources, [.detector, .regionClassifier])
        XCTAssertEqual(fused.boundingBox, box, "agreement keeps the detector's box")
        XCTAssertEqual(fused.detectorConfidence, 0.80)
        XCTAssertEqual(fused.classifierConfidence, 0.70)
    }

    func test_theDetectorAloneIsASingleSource() {
        let result = DetectionFusionService().fuse(detections: frame([detection("apple")]))

        let fused = try! XCTUnwrap(result.localised.first)
        XCTAssertEqual(fused.tier, .singleSource)
        XCTAssertEqual(fused.sources, .detector)
        XCTAssertTrue(fused.requiresReview, "one method is never enough to stop asking")
    }

    /// The shipped strategy, chosen on measurement: within a detector box the
    /// classifier was right 5 times out of 8 against the detector's 1 of 8.
    /// It is still marked uncertain, because 5 of 8 is not 8 of 8.
    func test_disagreementPrefersTheClassifierAndStaysUncertain() {
        let apple = detection("apple")
        let result = DetectionFusionService().fuse(
            detections: frame([apple]),
            regionClassifications: [apple.id: classified("tomato", category: .vegetable)]
        )

        let fused = try! XCTUnwrap(result.localised.first)
        XCTAssertEqual(fused.tier, .conflicting)
        XCTAssertEqual(fused.ingredientId, "tomato", "the classifier's label leads in a conflict")
        XCTAssertEqual(fused.category, .vegetable, "the category follows the label it came with")
        XCTAssertEqual(fused.conflictingClaim, "Apple", "the loser must survive, not be discarded")
        XCTAssertEqual(fused.boundingBox, box, "the box is still the detector's")
        XCTAssertTrue(fused.requiresReview)
        XCTAssertFalse(fused.isPreselected, "a disagreement is never pre-ticked")
    }

    // MARK: - Conflict strategies

    private func conflict(
        _ strategy: DetectionFusionService.ConflictStrategy,
        detectorConfidence: Float = 0.80,
        classifierConfidence: Float = 0.70
    ) -> FusedIngredient {
        let apple = detection("apple", detectorConfidence)
        let result = DetectionFusionService(configuration: .with(strategy)).fuse(
            detections: frame([apple]),
            regionClassifications: [
                apple.id: classified("tomato", classifierConfidence, category: .vegetable),
            ]
        )
        return result.localised.first!
    }

    func test_strategyAKeepsTheDetectorsLabel() {
        let fused = conflict(.preferDetector)

        XCTAssertEqual(fused.ingredientId, "apple")
        XCTAssertEqual(fused.conflictingClaim, "Tomato")
        XCTAssertTrue(fused.assertsIngredient)
    }

    func test_strategyBKeepsTheClassifiersLabel() {
        let fused = conflict(.preferClassifier)

        XCTAssertEqual(fused.ingredientId, "tomato")
        XCTAssertEqual(fused.conflictingClaim, "Apple")
    }

    func test_strategyCFollowsWhicheverIsMoreConfident() {
        XCTAssertEqual(
            conflict(.higherConfidence, detectorConfidence: 0.90, classifierConfidence: 0.40).ingredientId,
            "apple"
        )
        XCTAssertEqual(
            conflict(.higherConfidence, detectorConfidence: 0.40, classifierConfidence: 0.90).ingredientId,
            "tomato"
        )
    }

    /// "We don't know" has to be representable, or every disagreement gets
    /// silently rounded to one of two guesses.
    func test_strategyDAssertsNothingButKeepsTheRegion() {
        let fused = conflict(.deferToUser)

        XCTAssertFalse(fused.assertsIngredient)
        XCTAssertFalse(fused.isPreselected)
        XCTAssertNotNil(fused.boundingBox, "the region is real even when the label is not settled")
        XCTAssertEqual(fused.conflictingClaim, "Tomato", "both candidates stay visible")
        XCTAssertEqual(fused.reviewReason, .ambiguousClass)
    }

    func test_unassertedConflictsAreExcludedFromTheAssertedSet() {
        let apple = detection("apple")
        let deferred = DetectionFusionService(configuration: .with(.deferToUser)).fuse(
            detections: frame([apple]),
            regionClassifications: [apple.id: classified("tomato", category: .vegetable)]
        )

        XCTAssertTrue(deferred.assertedIngredientIds.isEmpty)
        XCTAssertEqual(deferred.localised.count, 1, "but it is still shown")
    }

    func test_everyStrategyKeepsTheConflictTier() {
        for strategy in DetectionFusionService.ConflictStrategy.allCases {
            XCTAssertEqual(conflict(strategy).tier, .conflicting,
                           "\(strategy) must not resolve a disagreement into certainty")
        }
    }

    /// A weak second opinion should not manufacture a conflict.
    func test_aLowConfidenceRegionClassificationIsIgnoredRatherThanTreatedAsConflict() {
        let apple = detection("apple")
        var configuration = DetectionFusionService.Configuration.default
        configuration.regionAgreementThreshold = 0.50

        let result = DetectionFusionService(configuration: configuration).fuse(
            detections: frame([apple]),
            regionClassifications: [apple.id: classified("tomato", 0.10, category: .vegetable)]
        )

        XCTAssertEqual(result.localised.first?.tier, .singleSource)
        XCTAssertNil(result.localised.first?.conflictingClaim)
    }

    // MARK: - The rule about whole-image labels

    /// The constraint this service exists to enforce.
    func test_wholeImageClassificationsNeverReceiveABoundingBox() {
        let result = DetectionFusionService().fuse(
            detections: frame([detection("apple")]),
            sceneClassification: classified("salmon_fillet", 0.90, category: .seafood)
        )

        let scene = try! XCTUnwrap(result.sceneLevel.first)
        XCTAssertEqual(scene.ingredientId, "salmon_fillet")
        XCTAssertNil(scene.boundingBox, "a whole-image label has no measured location")
        XCTAssertFalse(scene.isLocalised)
        XCTAssertEqual(scene.sources, .sceneClassifier)

        // And it must not have been attached to the detector's apple.
        XCTAssertEqual(result.localised.count, 1)
        XCTAssertEqual(result.localised.first?.ingredientId, "apple")
    }

    func test_sceneClaimsDoNotDuplicateSomethingAlreadyLocalised() {
        let result = DetectionFusionService().fuse(
            detections: frame([detection("apple")]),
            sceneClassification: classified("apple", 0.90)
        )

        XCTAssertTrue(result.sceneLevel.isEmpty, "one apple should not be listed twice")
        XCTAssertEqual(result.localised.count, 1)
    }

    func test_sceneClaimsBelowTheThresholdAreDropped() {
        let result = DetectionFusionService().fuse(
            detections: frame([]),
            sceneClassification: classified("banana", 0.10)
        )

        XCTAssertTrue(result.sceneLevel.isEmpty)
    }

    // MARK: - Ambiguity survives agreement

    /// Two methods both saying "red meat" does not make the species visible.
    func test_agreementDoesNotClearAnAmbiguousClassFlag() {
        let meat = detection("red_meat", 0.90, category: .meat, review: .ambiguousClass)
        let result = DetectionFusionService().fuse(
            detections: frame([meat]),
            regionClassifications: [meat.id: classified("red_meat", 0.85, category: .meat)]
        )

        let fused = try! XCTUnwrap(result.localised.first)
        XCTAssertEqual(fused.tier, .agreed, "support is high")
        XCTAssertEqual(fused.reviewReason, .ambiguousClass, "but the species is still unknown")
        XCTAssertTrue(fused.requiresReview)
    }

    /// Agreement is a suggestion, never an authorisation.
    func test_onlyAgreementIsPreselectedAndEvenThatIsJustADefault() {
        XCTAssertTrue(ConfidenceTier.agreed.isPreselected)
        XCTAssertFalse(ConfidenceTier.singleSource.isPreselected)
        XCTAssertFalse(ConfidenceTier.conflicting.isPreselected)
    }

    // MARK: - Ordering and counts

    func test_resultsAreOrderedByTierThenConfidence() {
        let agreed = detection("apple", 0.50)
        let alone = detection("banana", 0.95, box: otherBox)
        let result = DetectionFusionService().fuse(
            detections: frame([alone, agreed]),
            regionClassifications: [agreed.id: classified("apple", 0.60)]
        )

        XCTAssertEqual(result.all.map(\.ingredientId), ["apple", "banana"],
                       "agreement outranks a more confident single source")
        XCTAssertEqual(result.agreedCount, 1)
        XCTAssertEqual(result.conflictCount, 0)
    }

    func test_rejectedFoodClaimsAreCarriedNotDiscarded() {
        let apple = detection("apple")
        let withRejects = ClassificationResult(
            ingredients: [], rejectedFoodClaims: ["brownie", "guacamole"]
        )
        let result = DetectionFusionService().fuse(
            detections: frame([apple]),
            regionClassifications: [apple.id: withRejects],
            sceneClassification: ClassificationResult(ingredients: [], rejectedFoodClaims: ["brownie"])
        )

        XCTAssertEqual(result.rejectedFoodClaims, ["brownie", "guacamole"],
                       "deduplicated, but kept for diagnostics")
    }

    func test_anEmptyFrameFusesToNothing() {
        let result = DetectionFusionService().fuse(detections: frame([]))

        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.agreedCount, 0)
    }
}
