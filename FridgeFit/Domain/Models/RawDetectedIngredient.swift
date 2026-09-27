//
//  RawDetectedIngredient.swift
//  FridgeFit
//

import Foundation

/// One ingredient exactly as an `IngredientRecognitionService` reported it -
/// untrusted input.
///
/// Mirrors `RawSubstitutionSuggestion`: every field stays a raw primitive
/// because a generative model can't be trusted to only emit values from
/// our known enums. `category` and `confidence` stay strings rather than
/// `IngredientCategory` / `ModelStatedConfidence`, and nothing here says
/// anything about the pantry - only `DetectedIngredientNormalizer` may turn
/// this into a `DetectedIngredient`.
struct RawDetectedIngredient: Equatable, Codable {
    let name: String
    let category: String
    /// How many distinct units the model claimed were visible. `0` means
    /// "couldn't tell", which is the common case for a fridge photo.
    let visibleCount: Int
    let confidence: String

    init(name: String, category: String, visibleCount: Int, confidence: String) {
        self.name = name
        self.category = category
        self.visibleCount = visibleCount
        self.confidence = confidence
    }
}

/// Everything an `IngredientRecognitionService` returned for one image.
///
/// Holds raw, unvalidated detections only - see `RawDetectedIngredient`.
struct IngredientDetectionResult: Equatable {
    let ingredients: [RawDetectedIngredient]

    init(ingredients: [RawDetectedIngredient]) {
        self.ingredients = ingredients
    }

    static let empty = IngredientDetectionResult(ingredients: [])
}
