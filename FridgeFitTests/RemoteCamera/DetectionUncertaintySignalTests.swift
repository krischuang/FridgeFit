//
//  DetectionUncertaintySignalTests.swift
//  FridgeFitTests
//

import CoreGraphics
import Foundation
import XCTest
@testable import FridgeFit

/// Confident-but-wrong detections, and what actually catches them.
///
/// The measured position, from the 11-image annotated set:
///
/// - Raising the display threshold does **not** help. `eggs_carton` reads as
///   `orange` at 0.726 and `beef_raw` as `bread loaf` at 0.712; both survive
///   every threshold up to 0.70, and the most confident detection in the whole
///   set - `bell pepper` at 0.837 on `veg_mixed` - survives all of them. At
///   0.80 it is the only thing left in all 11 images, so precision is 0.0.
/// - Apple Vision classifying the same crop **does** help. The Swift harness
///   (`tools/vision-eval/swift-harness`) finds 11 conflicting regions across
///   the set, and they land on `beef_raw`, `eggs_carton`, `fish_platter`,
///   `veg_mixed` and `shelf_packaged` - which is where the detector's false
///   positives are. Scored by strategy, keeping the detector's label in those
///   regions was right 1 time out of 11; keeping the classifier's was right 8
///   times out of 11.
///
/// So the lever is corroboration, not a bigger number. These tests pin the
/// behaviour that implements it, and pin the honest limits of it too: there
/// are no hardcoded label mappings, the two confidences are never compared as
/// if they were on one scale, and agreement is not treated as proof.
final class DetectionUncertaintySignalTests: XCTestCase {

    private let box = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)

    private func detection(
        _ ingredient: String,
        _ confidence: Float = 0.80,
        category: IngredientGroup = .fruit,
        review: ReviewReason? = nil
    ) -> DetectedIngredient {
        DetectedIngredient(
            ingredientId: ingredient, displayName: ingredient.capitalized,
            category: category, confidence: confidence,
            boundingBox: box, source: .ingredientDetector,
            reviewReason: review, rawTerm: ingredient,
            band: DetectionFilterPolicy.default.band(for: confidence)
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
        category: IngredientGroup = .fruit
    ) -> ClassificationResult {
        ClassificationResult(
            ingredients: [ClassifiedIngredient(
                ingredientId: ingredient, displayName: ingredient.capitalized,
                category: category, confidence: confidence,
                rawIdentifier: ingredient, requiresReview: false
            )],
            rejectedFoodClaims: []
        )
    }

    // MARK: - Disagreement as a signal

    /// The `eggs_carton` case. The detector says `orange` at 0.726; Apple
    /// Vision, given the same crop, says something else. The region is kept,
    /// both candidate labels are kept, and nothing is presented as settled.
    func test_disagreementOnARegionIsRecordedRatherThanResolvedSilently() {
        let wrong = detection("orange", 0.726)
        let result = DetectionFusionService().fuse(
            detections: frame([wrong]),
            regionClassifications: [wrong.id: classified("egg", 0.55, category: .dairy)]
        )

        let fused = try! XCTUnwrap(result.localised.first)
        XCTAssertEqual(fused.tier, .conflicting)
        XCTAssertTrue(fused.requiresReview)
        XCTAssertFalse(fused.isPreselected, "a disagreement is never pre-ticked")
        // Both confidences survive, and so does the losing label, so the user
        // sees the disagreement rather than an arbitrary winner.
        XCTAssertEqual(fused.detectorConfidence, 0.726)
        XCTAssertEqual(fused.classifierConfidence, 0.55)
        XCTAssertNotNil(fused.conflictingClaim)
        XCTAssertEqual(fused.sources, [.detector, .regionClassifier])
    }

    /// High detector confidence does not win a disagreement by being high.
    ///
    /// The shipped strategy is `preferClassifier`, chosen because it measured
    /// best (62% conflict accuracy against 12% for `preferDetector`). What
    /// this test guards is that the *detector's* 0.726 does not override a
    /// classifier's 0.21 - the two numbers are not on a common scale, and
    /// comparing them is the mistake `higherConfidence` exists to measure, not
    /// the default.
    func test_aConfidentDetectorDoesNotOverrideTheClassifierByConfidenceAlone() {
        let wrong = detection("orange", 0.726)
        let result = DetectionFusionService().fuse(
            detections: frame([wrong]),
            regionClassifications: [wrong.id: classified("egg", 0.21, category: .dairy)]
        )

        let fused = try! XCTUnwrap(result.localised.first)
        XCTAssertEqual(fused.tier, .conflicting)
        XCTAssertEqual(fused.ingredientId, "egg",
                       "the shipped strategy is preferClassifier, not whoever scored higher")
        XCTAssertEqual(DetectionFusionService.Configuration.default.conflictStrategy,
                       .preferClassifier)
    }

    /// "We asked and it saw nothing" is weaker evidence than "we never asked",
    /// and the two must not collapse into one state.
    func test_aRegionTheClassifierExaminedAndDidNotSupportIsFlagged() {
        let lonely = detection("bread_loaf", 0.712, category: .pantry)
        let result = DetectionFusionService().fuse(
            detections: frame([lonely]),
            // Present but empty: the crop was classified, nothing came back.
            regionClassifications: [lonely.id: ClassificationResult.empty]
        )

        let fused = try! XCTUnwrap(result.localised.first)
        XCTAssertEqual(fused.tier, .singleSource)
        XCTAssertEqual(fused.reviewReason, .notCorroborated)
        XCTAssertTrue(fused.requiresReview)
        XCTAssertFalse(fused.isPreselected)
    }

    func test_aRegionNobodyClassifiedIsNotFlaggedAsUncorroborated() {
        let lonely = detection("bread_loaf", 0.712, category: .pantry)
        let result = DetectionFusionService().fuse(
            detections: frame([lonely]),
            regionClassifications: [:]
        )

        let fused = try! XCTUnwrap(result.localised.first)
        XCTAssertEqual(fused.tier, .singleSource)
        XCTAssertNil(fused.reviewReason,
                     "never having asked is not evidence against the claim")
    }

    /// A weak second opinion is ignored rather than treated as a conflict -
    /// but the region still records that it was examined.
    func test_aSubThresholdClassificationCountsAsExaminedNotAsDisagreement() {
        let detected = detection("apple", 0.70)
        let result = DetectionFusionService().fuse(
            detections: frame([detected]),
            // Below `regionAgreementThreshold` (0.20).
            regionClassifications: [detected.id: classified("pear", 0.05)]
        )

        let fused = try! XCTUnwrap(result.localised.first)
        XCTAssertEqual(fused.tier, .singleSource, "0.05 is not a second opinion")
        XCTAssertEqual(fused.reviewReason, .notCorroborated)
        XCTAssertEqual(fused.ingredientId, "apple")
    }

    /// An existing, more specific reason is not overwritten by the generic
    /// "nobody corroborated it" one.
    func test_anAmbiguousClassKeepsItsOwnReasonWhenUncorroborated() {
        let meat = detection("red_meat", 0.92, category: .meat, review: .ambiguousClass)
        let result = DetectionFusionService().fuse(
            detections: frame([meat]),
            regionClassifications: [meat.id: ClassificationResult.empty]
        )

        XCTAssertEqual(result.localised.first?.reviewReason, .ambiguousClass)
    }

    // MARK: - What corroboration is and is not

    /// Agreement is the best tier and still not proof. On `market_crowded`
    /// both methods independently reported "pumpkin" and there is no pumpkin
    /// in the photograph - 5 of 6 agreements correct, 83.3%.
    func test_agreementIsPreselectedButStillRequiresTheUserToConfirm() {
        let apple = detection("apple", 0.85)
        let result = DetectionFusionService().fuse(
            detections: frame([apple]),
            regionClassifications: [apple.id: classified("apple", 0.74)]
        )

        let fused = try! XCTUnwrap(result.localised.first)
        XCTAssertEqual(fused.tier, .agreed)
        XCTAssertTrue(fused.isPreselected, "agreement is a default, worth offering")
        XCTAssertTrue(fused.assertsIngredient)
        // And it is still only a pre-tick in a sheet the user accepts; nothing
        // in fusion writes to the pantry.
    }

    /// No label is ever rewritten into a different one by rule. A wrong
    /// `orange` on a carton of eggs stays an `orange` claim that the user
    /// rejects - it is never silently remapped to `egg`.
    func test_thereIsNoHardcodedRemappingOfKnownMistakes() {
        let wrong = detection("orange", 0.726)
        let unexamined = DetectionFusionService().fuse(
            detections: frame([wrong]), regionClassifications: [:]
        )

        XCTAssertEqual(unexamined.localised.first?.ingredientId, "orange",
                       "with no second opinion the detector's own label stands, wrong or not")
        XCTAssertEqual(unexamined.localised.first?.detectorTerm, "orange")
    }

    // MARK: - Live detections are never verified

    /// The live path has no second method, so nothing it produces may be
    /// presented as confirmed however high the confidence.
    func test_noLiveDetectionIsEverVerifiedRegardlessOfConfidence() {
        for confidence in [Float(0.40), 0.60, 0.80, 0.99] {
            let candidate = detection("apple", confidence)
            XCTAssertFalse(candidate.isVerified, "\(confidence) must not be verified")
            XCTAssertTrue(candidate.requiresConfirmation)
        }
    }

    /// And the band, which *is* allowed to vary, only changes presentation.
    func test_theStrongBandIsReachableButVerificationIsNot() {
        XCTAssertEqual(detection("apple", 0.85).band, .strong)
        XCTAssertEqual(detection("apple", 0.45).band, .tentative)
        XCTAssertFalse(detection("apple", 0.85).isVerified)
    }

    // MARK: - Stage separation

    /// Task 6's requirement, as a test: a candidate the overlay hides must
    /// still be able to reach the review sheet when a second method names it.
    func test_aDetectionHiddenFromTheOverlayStillReachesReviewWhenCorroborated() {
        let policy = DetectionFilterPolicy.default
        // 0.34: above the candidate floor, below the display floor.
        let weak = detection("apple", 0.34)
        XCTAssertGreaterThanOrEqual(weak.confidence, policy.candidateThreshold)
        XCTAssertLessThan(weak.confidence, policy.displayThreshold)

        var filter = DetectionDisplayFilter(policy: policy)
        let drawn = filter.display(frame([weak]), at: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(drawn.isEmpty, "the overlay withholds it")

        // Fusion works from stage 2, not stage 3, so it is still there.
        let fused = DetectionFusionService().fuse(
            detections: frame([weak]),
            regionClassifications: [weak.id: classified("apple", 0.66)]
        )
        XCTAssertEqual(fused.localised.first?.tier, .agreed,
                       "a hidden box that Apple Vision confirms must not be lost")
    }

    /// The review floor is its own setting and can refuse a candidate the
    /// normaliser kept.
    func test_theReviewThresholdIsSeparateFromTheDisplayThreshold() {
        var configuration = DetectionFusionService.Configuration.default
        configuration.detectorThreshold = 0.50
        let service = DetectionFusionService(configuration: configuration)

        let result = service.fuse(detections: frame([detection("apple", 0.45)]))

        XCTAssertTrue(result.localised.isEmpty)
        XCTAssertEqual(DetectionFusionService.Configuration.default.detectorThreshold,
                       DetectionFilterPolicy.default.reviewThreshold)
    }
}
