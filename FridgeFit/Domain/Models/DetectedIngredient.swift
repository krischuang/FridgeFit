//
//  DetectedIngredient.swift
//  FridgeFit
//

import Foundation

/// A scan detection after deterministic normalization - what the review
/// screen is allowed to show.
///
/// `category` and `confidence` are real enums by this point, and
/// `isAlreadyInPantry` comes from checking the actual pantry in
/// `DetectIngredientsUseCase`, never from the model. Still not a pantry
/// item: nothing reaches the pantry until the user confirms it.
struct DetectedIngredient: Identifiable, Equatable {
    let id: UUID
    let name: String
    let category: IngredientCategory
    /// Units the model claimed to see, already clamped to a sane range.
    /// `nil` when the model couldn't tell.
    let visibleCount: Int?
    let confidence: ModelStatedConfidence
    /// Set by `DetectIngredientsUseCase` from the real pantry, so the
    /// review screen can warn before `AddPantryItemUseCase` rejects it as
    /// a duplicate.
    let isAlreadyInPantry: Bool

    init(
        id: UUID = UUID(),
        name: String,
        category: IngredientCategory,
        visibleCount: Int?,
        confidence: ModelStatedConfidence,
        isAlreadyInPantry: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.visibleCount = visibleCount
        self.confidence = confidence
        self.isAlreadyInPantry = isAlreadyInPantry
    }

    /// Copy of this detection with pantry knowledge applied.
    func markingAlreadyInPantry(_ isAlreadyInPantry: Bool) -> DetectedIngredient {
        DetectedIngredient(
            id: id,
            name: name,
            category: category,
            visibleCount: visibleCount,
            confidence: confidence,
            isAlreadyInPantry: isAlreadyInPantry
        )
    }
}
