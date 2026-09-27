//
//  GeneratedFridgeInventory.swift
//  FridgeFit
//

import FoundationModels

/// The guided-generation schema the on-device model fills in for a fridge
/// scan.
///
/// Provider-specific on purpose - these types exist to constrain
/// `FoundationModels` output and nothing else, which is why they live in
/// the data layer and get mapped straight onto `RawDetectedIngredient`
/// rather than being passed around the app.
///
/// Two deliberate schema choices:
///
/// - No `Optional` properties. Guided generation is happier producing a
///   sentinel than an absent field, so "I couldn't tell how many" is
///   `visibleCount == 0` rather than `nil`.
/// - Category and confidence are `@Generable` enums, not free strings, so
///   the model can only pick a value FridgeFit already understands. The
///   cases mirror `IngredientCategory` / `ModelStatedConfidence` one for
///   one; mapping happens in `GeneratedFridgeInventory.rawDetections`.
@Generable(description: "Food ingredients identified in a photo of the inside of a refrigerator")
struct GeneratedFridgeInventory {
    @Guide(
        description: "Every distinct food ingredient clearly visible in the photo. Empty if no food can be identified.",
        .maximumCount(25)
    )
    var ingredients: [GeneratedIngredient]
}

@Generable(description: "A single food ingredient visible in a refrigerator photo")
struct GeneratedIngredient {
    @Guide(description: "Simple lowercase ingredient name, such as 'milk', 'tomato' or 'chicken breast'. No brand names, quantities or packaging words.")
    var name: String

    @Guide(description: "Which food group this ingredient belongs to")
    var category: GeneratedIngredientCategory

    @Guide(
        description: "How many separate units of this ingredient are clearly countable in the photo. Use 0 if you cannot count them.",
        .range(0...50)
    )
    var visibleCount: Int

    @Guide(description: "How certain you are that this ingredient is really present in the photo")
    var confidence: GeneratedConfidence
}

/// Mirrors `IngredientCategory`. Kept separate so the shared domain model
/// doesn't have to import `FoundationModels`.
@Generable
enum GeneratedIngredientCategory {
    case produce
    case dairy
    case meat
    case grain
    case spiceOrCondiment
    case other
}

/// Mirrors `ModelStatedConfidence`.
@Generable
enum GeneratedConfidence {
    case high
    case medium
    case low
}

extension GeneratedFridgeInventory {
    /// Flattens the generated inventory into untrusted raw detections.
    ///
    /// Only translation happens here - no filtering, trimming or
    /// de-duplication. That's `DetectedIngredientNormalizer`'s job, so
    /// there's a single place those rules live regardless of which provider
    /// produced the detections.
    var rawDetections: [RawDetectedIngredient] {
        ingredients.map { ingredient in
            RawDetectedIngredient(
                name: ingredient.name,
                category: ingredient.category.ingredientCategory.rawValue,
                visibleCount: ingredient.visibleCount,
                confidence: ingredient.confidence.modelStatedConfidence.rawValue
            )
        }
    }
}

extension GeneratedIngredientCategory {
    var ingredientCategory: IngredientCategory {
        switch self {
        case .produce: return .produce
        case .dairy: return .dairy
        case .meat: return .meat
        case .grain: return .grain
        case .spiceOrCondiment: return .spice
        case .other: return .other
        }
    }
}

extension GeneratedConfidence {
    var modelStatedConfidence: ModelStatedConfidence {
        switch self {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        }
    }
}
