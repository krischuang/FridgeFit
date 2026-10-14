//
//  IngredientDetectorFactory.swift
//  FridgeFit
//

import Foundation
import OSLog

/// A loaded detector together with everything needed to interpret it.
nonisolated struct ResolvedDetector: Sendable {
    let detector: any FrameDetecting
    let normalizer: IngredientNormalizer
    let source: DetectionSource
    /// Non-nil when the preferred model could not be loaded and this is the
    /// fallback. Shown to the user so a degraded run is never silent.
    let fallbackReason: String?

    var taxonomy: IngredientTaxonomy { normalizer.taxonomy }
}

/// Chooses which detector to run.
///
/// Prefers the YOLO-World ingredient model; falls back to the original COCO
/// YOLO11n if that cannot be loaded. Only one model is ever constructed, so a
/// constrained device never holds both in memory.
///
/// The fallback is not decorative. YOLO11n is the model whose behaviour is
/// already verified end to end, and keeping it means a bad ingredient-model
/// export degrades to ten reliable food classes rather than to nothing.
nonisolated enum IngredientDetectorFactory {
    static let logger = Logger(subsystem: "com.Fridge.FridgeFit", category: "DetectorFactory")

    /// Bundle resource name of the YOLO-World export.
    static let ingredientModelName = "FridgeFitIngredients"
    /// Bundle resource name of the COCO fallback.
    static let fallbackModelName = "YOLO11n"

    /// Loads the best detector available.
    ///
    /// - Throws: only if *both* models are unavailable - at that point there
    ///   is nothing to run and the caller reports it rather than pretending.
    static func makeBest(bundle: Bundle = .main) throws -> ResolvedDetector {
        do {
            return try makeIngredientDetector(bundle: bundle)
        } catch {
            let reason = (error as? YOLODetectionError)?.message
                ?? (error as? IngredientTaxonomy.LoadError)?.message
                ?? error.localizedDescription
            logger.error("Ingredient model unavailable, falling back: \(reason, privacy: .public)")

            let fallback = try makeFallbackDetector(bundle: bundle)
            return ResolvedDetector(
                detector: fallback.detector,
                normalizer: fallback.normalizer,
                source: .cocoFallback,
                fallbackReason: reason
            )
        }
    }

    /// YOLO-World with FridgeFit's ingredient vocabulary.
    static func makeIngredientDetector(bundle: Bundle = .main) throws -> ResolvedDetector {
        let taxonomy = try IngredientTaxonomy.load(in: bundle)

        var configuration = YOLOFoodDetectionService.Configuration.default
        configuration.modelName = ingredientModelName
        // Every term, decoys included. Decoys have to be *allowed through the
        // model* so non-food objects land on them instead of being forced
        // onto a food class; `IngredientNormalizer` drops them afterwards.
        configuration.allowedLabels = taxonomy.allTerms
        // The real gate is the normaliser's display threshold. Keeping the
        // model's own threshold just below it leaves the policy in one place.
        configuration.confidenceThreshold = IngredientNormalizer.Configuration.default.displayThreshold - 0.05
        // Generous, because decoys consume slots before normalisation.
        configuration.maximumDetections = 40

        let detector = try YOLOFoodDetectionService(configuration: configuration, bundle: bundle)
        logger.info("""
        Ingredient detector loaded: \(taxonomy.ingredientCount) ingredients, \
        \(taxonomy.definitions.count) vocabulary terms, model \(taxonomy.modelIdentifier, privacy: .public)
        """)
        return ResolvedDetector(
            detector: detector,
            normalizer: IngredientNormalizer(taxonomy: taxonomy),
            source: .ingredientDetector,
            fallbackReason: nil
        )
    }

    /// The original COCO detector, wrapped in the same ingredient interface.
    static func makeFallbackDetector(bundle: Bundle = .main) throws -> ResolvedDetector {
        var configuration = YOLOFoodDetectionService.Configuration.default
        configuration.modelName = fallbackModelName
        configuration.allowedLabels = COCOFoodClass.all
        configuration.confidenceThreshold = 0.45

        let detector = try YOLOFoodDetectionService(configuration: configuration, bundle: bundle)
        // COCO's confidences are better calibrated than the open-vocabulary
        // model's, so this path keeps the thresholds it was tuned with.
        var policy = IngredientNormalizer.Configuration.default
        policy.displayThreshold = 0.45
        policy.trustThreshold = 0.60

        return ResolvedDetector(
            detector: detector,
            normalizer: IngredientNormalizer(taxonomy: .coco, configuration: policy),
            source: .cocoFallback,
            fallbackReason: nil
        )
    }
}

// MARK: - COCO taxonomy

nonisolated extension IngredientTaxonomy {
    /// The ten edible COCO classes, as a taxonomy.
    ///
    /// Hard-coded rather than loaded from JSON because it describes a model
    /// that ships with the app and whose class list cannot change.
    static let coco: IngredientTaxonomy = {
        func entry(_ term: String, _ display: String, _ category: IngredientGroup) -> IngredientDefinition {
            IngredientDefinition(
                term: term,
                ingredient: term.replacingOccurrences(of: " ", with: "_"),
                display: display,
                category: category,
                requiresReview: false,
                genericFallback: nil
            )
        }
        return IngredientTaxonomy(
            version: 1,
            modelIdentifier: "yolo11n-coco",
            definitions: [
                entry("apple", "Apple", .fruit),
                entry("banana", "Banana", .fruit),
                entry("orange", "Orange", .fruit),
                entry("broccoli", "Broccoli", .vegetable),
                entry("carrot", "Carrot", .vegetable),
                entry("sandwich", "Sandwich", .pantry),
                entry("hot dog", "Hot Dog", .pantry),
                entry("pizza", "Pizza", .pantry),
                entry("donut", "Donut", .pantry),
                entry("cake", "Cake", .pantry),
            ]
        )
    }()
}
