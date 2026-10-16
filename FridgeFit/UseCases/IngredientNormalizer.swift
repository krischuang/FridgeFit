//
//  IngredientNormalizer.swift
//  FridgeFit
//

import CoreGraphics
import Foundation

/// Raw model detections to **accepted candidate ingredients** - stage 2 of the
/// four stages `DetectionFilterPolicy` documents.
///
/// This is where the app decides what it is *willing to consider*. What it is
/// willing to *draw* is a narrower question, answered one stage later by
/// `DetectionDisplayFilter`. Splitting the two is deliberate: the snapshot
/// pipeline reads stage 2, so a box too weak for the live overlay is still
/// available for Apple Vision and OCR to corroborate, and a detection hidden
/// from the Controller never silently vanishes from analysis.
///
/// Measured precision of the ingredient model on the evaluation set is 55.6%
/// at the display floor (see `docs/detection-confidence-filtering.md`), so
/// everything here is biased towards saying less:
///
/// - terms below `candidateThreshold` are dropped entirely
/// - classes the model cannot honestly separate (raw beef vs lamb vs pork)
///   collapse to a generic ingredient and are always flagged
/// - decoy terms (plate, hand, shelf) are dropped - they exist to absorb
///   non-food, not to be reported
/// - overlapping boxes of the *same* ingredient are merged
///
/// Nothing here marks anything verified. Every candidate it produces came from
/// one method, and `DetectedIngredient.isVerified` is `false` by construction.
///
/// Pure and synchronous, so the policy is testable without a model.
nonisolated struct IngredientNormalizer: Sendable {

    let taxonomy: IngredientTaxonomy
    let policy: DetectionFilterPolicy

    init(taxonomy: IngredientTaxonomy, policy: DetectionFilterPolicy = .default) {
        self.taxonomy = taxonomy
        self.policy = policy
    }

    /// Normalises one frame of raw detections into candidates.
    ///
    /// The result is *not* what the overlay draws. Pass it through
    /// `DetectionDisplayFilter` for that.
    func normalize(_ frame: DetectionFrame, source: DetectionSource) -> IngredientDetectionFrame {
        var candidates: [DetectedIngredient] = []

        for object in frame.objects {
            guard let definition = taxonomy.definition(forTerm: object.label) else { continue }
            // Decoys did their job by absorbing a non-food object; they are
            // not results. This is the "exclude verified non-food classes"
            // rule, and it is applied before anything else can see them.
            guard definition.category.isIngredient else { continue }
            guard object.confidence >= policy.candidateThreshold else { continue }

            // An ambiguous class reports its generic identity rather than
            // asserting a species the model cannot actually see.
            let isAmbiguous = definition.requiresReview
            let ingredientId = isAmbiguous ? (definition.genericFallback ?? definition.ingredient)
                                           : definition.ingredient
            let displayName = isAmbiguous
                ? Self.genericDisplayName(for: ingredientId, taxonomy: taxonomy, fallback: definition.display)
                : definition.display

            let reason: ReviewReason? = {
                if isAmbiguous { return .ambiguousClass }
                if object.confidence < policy.strongThreshold { return .lowConfidence }
                // No reason does not mean trusted - see `isVerified`, which is
                // always false on this type. It means nothing *additional* is
                // wrong beyond it being one method's opinion.
                return nil
            }()

            candidates.append(DetectedIngredient(
                ingredientId: ingredientId,
                displayName: displayName,
                category: definition.category,
                confidence: object.confidence,
                boundingBox: object.boundingBox,
                source: source,
                reviewReason: reason,
                rawTerm: definition.term,
                band: policy.band(for: object.confidence)
            ))
        }

        let deduplicated = Self.suppressDuplicates(
            in: candidates.sorted { $0.confidence > $1.confidence },
            iouThreshold: policy.duplicateIoU
        )
        return IngredientDetectionFrame(
            ingredients: Array(deduplicated.prefix(policy.maximumCandidates)),
            sourceSize: frame.sourceSize,
            source: source
        )
    }

    /// Drops lower-confidence boxes that substantially overlap a kept box of
    /// the same ingredient.
    ///
    /// The model's own NMS already suppresses per class, but two *different*
    /// vocabulary terms mapping to one ingredient - "raw beef steak" and
    /// "minced beef" both becoming `red_meat` - survive it and would be drawn
    /// as two boxes on one object.
    ///
    /// Deliberately only applied within an ingredient identity, and at a high
    /// IoU. A tomato resting on a lettuce leaf is two real things, and so are
    /// two apples touching in a bowl. Suppressing across ingredients was
    /// measured and made things worse; see `DetectionFilterPolicy`.
    ///
    /// - Parameter candidates: must be sorted by descending confidence.
    static func suppressDuplicates(
        in candidates: [DetectedIngredient],
        iouThreshold: CGFloat
    ) -> [DetectedIngredient] {
        var kept: [DetectedIngredient] = []
        for candidate in candidates {
            let overlapsKept = kept.contains { existing in
                existing.ingredientId == candidate.ingredientId
                    && intersectionOverUnion(existing.boundingBox, candidate.boundingBox) > iouThreshold
            }
            if !overlapsKept { kept.append(candidate) }
        }
        return kept
    }

    /// Standard IoU for two normalised rects.
    static func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    /// Display name for a generic identifier, taken from the taxonomy if a
    /// term defines it directly, otherwise prettified.
    static func genericDisplayName(
        for ingredientId: String,
        taxonomy: IngredientTaxonomy,
        fallback: String
    ) -> String {
        if let exact = taxonomy.definitions.first(where: {
            $0.ingredient == ingredientId && !$0.requiresReview
        }) {
            return exact.display
        }
        // "red_meat" -> "Red Meat"
        let prettified = ingredientId
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        return prettified.isEmpty ? fallback : prettified
    }
}
