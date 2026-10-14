//
//  IngredientNormalizer.swift
//  FridgeFit
//

import CoreGraphics
import Foundation

/// Turns raw model detections into candidate ingredients.
///
/// This is where the app decides what it is willing to claim. Measured
/// precision of the ingredient model on the evaluation set is around 56% at
/// the default threshold (see docs/general-ingredient-detection.md), so
/// everything here is biased towards saying less:
///
/// - terms below `displayThreshold` are dropped entirely
/// - terms between `displayThreshold` and `trustThreshold` are shown but
///   flagged for review
/// - classes the model cannot honestly separate (raw beef vs lamb vs pork)
///   collapse to a generic ingredient and are always flagged
/// - decoy terms (plate, hand, shelf) are dropped - they exist to absorb
///   non-food, not to be reported
/// - overlapping boxes for the same ingredient are suppressed
///
/// Pure and synchronous, so the policy is testable without a model.
nonisolated struct IngredientNormalizer: Sendable {

    nonisolated struct Configuration: Sendable {
        /// Below this, nothing is shown at all.
        ///
        /// 0.40 was chosen from a threshold sweep over the annotated
        /// evaluation set: it holds recall level with 0.35 while lifting
        /// precision from ~42% to ~56% and halving false positives.
        var displayThreshold: Float = 0.40
        /// At or above this, a detection is shown without a review flag.
        var trustThreshold: Float = 0.60
        /// Two boxes of the same ingredient overlapping by more than this are
        /// treated as one object.
        var duplicateIoU: CGFloat = 0.55
        /// Cap on ingredients drawn per frame, best first.
        var maximumIngredients: Int = 12

        static let `default` = Configuration()
    }

    let taxonomy: IngredientTaxonomy
    let configuration: Configuration

    init(taxonomy: IngredientTaxonomy, configuration: Configuration = .default) {
        self.taxonomy = taxonomy
        self.configuration = configuration
    }

    /// Normalises one frame of raw detections.
    func normalize(_ frame: DetectionFrame, source: DetectionSource) -> IngredientDetectionFrame {
        var candidates: [DetectedIngredient] = []

        for object in frame.objects {
            guard let definition = taxonomy.definition(forTerm: object.label) else { continue }
            // Decoys did their job by absorbing a non-food object; they are
            // not results.
            guard definition.category.isIngredient else { continue }
            guard object.confidence >= configuration.displayThreshold else { continue }

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
                if object.confidence < configuration.trustThreshold { return .lowConfidence }
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
                rawTerm: definition.term
            ))
        }

        let deduplicated = Self.suppressDuplicates(
            in: candidates.sorted { $0.confidence > $1.confidence },
            iouThreshold: configuration.duplicateIoU
        )
        return IngredientDetectionFrame(
            ingredients: Array(deduplicated.prefix(configuration.maximumIngredients)),
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
    /// as two boxes on one object. Deliberately only applied within an
    /// ingredient: a tomato resting on a lettuce leaf is two real things.
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
