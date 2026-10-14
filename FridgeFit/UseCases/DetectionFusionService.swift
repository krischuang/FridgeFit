//
//  DetectionFusionService.swift
//  FridgeFit
//

import CoreGraphics
import Foundation

/// Combines what the detector saw with what the classifier recognised, and
/// grades how well supported each claim is.
///
/// ## The rule that shapes everything here
///
/// A classification may only be attached to a box when it was computed *from
/// that box*. Region classifications come from `DetectionRegionCropper`,
/// which cuts the detector's own rectangle out of the frame, so pairing them
/// is a statement about the same pixels. Whole-image classification is a
/// statement about the frame, and is kept in `sceneLevel` with no box.
///
/// Merging whole-image labels into the detector's rectangles would
/// manufacture localisation that was never measured: Vision saying "salmon"
/// about a photo plus YOLO drawing a box around a lemon does not mean the box
/// contains salmon. That is the single easiest way to make this pipeline look
/// better than it is, and it is why the two lists never merge.
///
/// ## Why agreement is worth anything
///
/// The detector and the classifier are genuinely independent: different
/// training data, different architectures, different failure modes. On the
/// evaluation set they failed in different categories - YOLO-World was the
/// only one to score on pantry items, Apple Vision the only one to score on
/// seafood and dairy. Independent methods converging is therefore evidence.
///
/// It is not proof. Agreement was correct 9 times out of 9 on an 11-image
/// set, which establishes that no counter-example has been seen, not that
/// none exists.
nonisolated struct DetectionFusionService: Sendable {

    /// What to do when the detector and the classifier disagree about the
    /// same region.
    ///
    /// Measured on the annotated set rather than chosen on intuition; see
    /// `docs/hybrid-stage2-results.md` for the comparison and the choice.
    /// Every option keeps the item marked `.conflicting`, so an explicit
    /// uncertain state survives whichever label is shown.
    nonisolated enum ConflictStrategy: String, CaseIterable, Sendable {
        /// A - keep the detector's label, because the box is the detector's.
        case preferDetector
        /// B - keep the classifier's label for the crop it classified.
        case preferClassifier
        /// C - whichever of the two is more confident.
        ///
        /// Note the two confidences are not on a common scale: a detector
        /// softmax and a Vision calibrated score mean different things. This
        /// option is measured precisely because that objection is easy to
        /// make and hard to settle by argument.
        case higherConfidence
        /// D - contribute nothing automatically. The region still appears,
        /// carrying both candidate labels, but neither is asserted.
        case deferToUser
    }

    nonisolated struct Configuration: Sendable {
        /// A region classification below this is ignored rather than treated
        /// as a disagreement. A weak second opinion is not a conflict.
        var regionAgreementThreshold: Float = 0.20
        /// Scene-level claims below this are dropped. Higher than the region
        /// floor because a scene claim has no location to corroborate it.
        var sceneThreshold: Float = 0.30
        /// Cap on scene-level claims.
        var maximumSceneIngredients: Int = 8
        /// How disagreements are resolved.
        var conflictStrategy: ConflictStrategy = .preferClassifier

        static let `default` = Configuration()

        static func with(_ strategy: ConflictStrategy) -> Configuration {
            var configuration = Configuration()
            configuration.conflictStrategy = strategy
            return configuration
        }
    }

    let configuration: Configuration

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    /// Fuses one frame's worth of evidence.
    ///
    /// - Parameters:
    ///   - detections: normalised detector output, with boxes.
    ///   - regionClassifications: classifier output keyed by the
    ///     `DetectedIngredient.id` of the box each crop came from. Only
    ///     entries produced by cropping that exact box belong here.
    ///   - sceneClassification: whole-image classification. Never attached to
    ///     a box.
    func fuse(
        detections: IngredientDetectionFrame,
        regionClassifications: [UUID: ClassificationResult] = [:],
        sceneClassification: ClassificationResult = .empty
    ) -> FusedDetectionFrame {
        var localised: [FusedIngredient] = []

        for detection in detections.ingredients {
            let best = regionClassifications[detection.id]?.ingredients
                .filter { $0.confidence >= configuration.regionAgreementThreshold }
                .max { $0.confidence < $1.confidence }

            localised.append(fuse(detection: detection, regionBest: best))
        }

        // Anything the classifier found in a region that the detector did not
        // name at all is not promoted to a localised claim: the box came from
        // the detector, so a classification of it that disagrees is handled
        // above as a conflict, and there is no second box to attach.

        let claimedIngredients = Set(localised.map(\.ingredientId))
        let sceneLevel = sceneIngredients(
            from: sceneClassification, excluding: claimedIngredients
        )

        var rejected = sceneClassification.rejectedFoodClaims
        for result in regionClassifications.values {
            rejected.append(contentsOf: result.rejectedFoodClaims)
        }

        return FusedDetectionFrame(
            localised: localised.sorted {
                $0.tier == $1.tier ? $0.confidence > $1.confidence : $0.tier > $1.tier
            },
            sceneLevel: sceneLevel,
            sourceSize: detections.sourceSize,
            rejectedFoodClaims: Array(Set(rejected)).sorted()
        )
    }

    // MARK: - One region

    private func fuse(
        detection: DetectedIngredient,
        regionBest: ClassifiedIngredient?
    ) -> FusedIngredient {
        guard let classified = regionBest else {
            // Detector only. Still carries whatever review reason the
            // normaliser already assigned - a generic "Red Meat" stays
            // generic.
            return FusedIngredient(
                ingredientId: detection.ingredientId,
                displayName: detection.displayName,
                category: detection.category,
                tier: .singleSource,
                sources: .detector,
                boundingBox: detection.boundingBox,
                detectorConfidence: detection.confidence,
                detectorTerm: detection.rawTerm,
                reviewReason: detection.reviewReason
            )
        }

        if classified.ingredientId == detection.ingredientId {
            // Both methods, same region, same answer.
            //
            // An ambiguous class stays flagged even here: two methods both
            // saying "red meat" does not make the species visible. The tier
            // records the support; the review reason records the open
            // question. They are different facts.
            return FusedIngredient(
                ingredientId: detection.ingredientId,
                displayName: detection.displayName,
                category: detection.category,
                tier: .agreed,
                sources: [.detector, .regionClassifier],
                boundingBox: detection.boundingBox,
                detectorConfidence: detection.confidence,
                classifierConfidence: classified.confidence,
                detectorTerm: detection.rawTerm,
                classifierIdentifier: classified.rawIdentifier,
                reviewReason: detection.reviewReason ?? (classified.requiresReview ? .ambiguousClass : nil)
            )
        }

        // Same pixels, two different answers. Which label leads is the
        // measured decision in `ConflictStrategy`; the box, both confidences
        // and the losing claim are kept whichever way it goes, so the user
        // always sees both rather than an arbitrary winner.
        let classifierLeads: Bool
        switch configuration.conflictStrategy {
        case .preferDetector:
            classifierLeads = false
        case .preferClassifier:
            classifierLeads = true
        case .higherConfidence:
            classifierLeads = classified.confidence > detection.confidence
        case .deferToUser:
            // Nothing is asserted. The detector's label is shown only as the
            // box's existing caption; `assertsIngredient` is false, so
            // evaluation and preselection both ignore it.
            return FusedIngredient(
                ingredientId: detection.ingredientId,
                displayName: detection.displayName,
                category: detection.category,
                tier: .conflicting,
                sources: [.detector, .regionClassifier],
                boundingBox: detection.boundingBox,
                detectorConfidence: detection.confidence,
                classifierConfidence: classified.confidence,
                detectorTerm: detection.rawTerm,
                classifierIdentifier: classified.rawIdentifier,
                conflictingClaim: classified.displayName,
                reviewReason: .ambiguousClass,
                assertsIngredient: false
            )
        }

        return FusedIngredient(
            ingredientId: classifierLeads ? classified.ingredientId : detection.ingredientId,
            displayName: classifierLeads ? classified.displayName : detection.displayName,
            category: classifierLeads ? classified.category : detection.category,
            tier: .conflicting,
            sources: [.detector, .regionClassifier],
            boundingBox: detection.boundingBox,
            detectorConfidence: detection.confidence,
            classifierConfidence: classified.confidence,
            detectorTerm: detection.rawTerm,
            classifierIdentifier: classified.rawIdentifier,
            conflictingClaim: classifierLeads ? detection.displayName : classified.displayName,
            reviewReason: detection.reviewReason ?? .lowConfidence
        )
    }

    // MARK: - Scene level

    /// Whole-image claims, with no box, excluding anything already localised.
    ///
    /// Deduplicating against localised claims keeps the review list from
    /// showing "Orange" twice - once with a box and once without - which
    /// would read as two oranges.
    private func sceneIngredients(
        from classification: ClassificationResult,
        excluding claimed: Set<String>
    ) -> [FusedIngredient] {
        classification.ingredients
            .filter { $0.confidence >= configuration.sceneThreshold }
            .filter { !claimed.contains($0.ingredientId) }
            .sorted { $0.confidence > $1.confidence }
            .prefix(configuration.maximumSceneIngredients)
            .map { classified in
                FusedIngredient(
                    ingredientId: classified.ingredientId,
                    displayName: classified.displayName,
                    category: classified.category,
                    tier: .singleSource,
                    sources: .sceneClassifier,
                    boundingBox: nil,
                    classifierConfidence: classified.confidence,
                    classifierIdentifier: classified.rawIdentifier,
                    reviewReason: classified.requiresReview ? .ambiguousClass : .lowConfidence
                )
            }
    }
}
