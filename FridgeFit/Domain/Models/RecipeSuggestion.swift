//
//  RecipeSuggestion.swift
//  FridgeFit
//

import Foundation

/// A recipe idea from a `RecipeSuggestionService` exactly as it came back -
/// untrusted input.
///
/// Every ingredient list stays a plain string array, and there is
/// deliberately no "available"/"missing" split here: what the pantry
/// contains is not something a generative model is allowed to assert. The
/// split is recomputed from the real pantry in
/// `SuggestRecipesFromPantryUseCase`.
struct RawRecipeSuggestion: Equatable, Codable {
    let name: String
    /// Ingredients the model says the recipe needs, in its own words.
    let requiredIngredients: [String]
    let shortInstructions: String
    /// Minutes, as the model estimated. `0` means it didn't say.
    let estimatedPreparationMinutes: Int
}

/// A recipe idea after its ingredients have been checked against the real
/// pantry - what the UI is allowed to show.
///
/// `availableIngredients` and `missingIngredients` are computed by
/// `SuggestRecipesFromPantryUseCase` reading `PantryRepository`, using the
/// same name-matching rule as `EvaluateRecipeFeasibilityUseCase`. If the
/// model claims an ingredient is on hand and the pantry disagrees, the
/// pantry wins and it lands in `missingIngredients`.
///
/// This never replaces `RecipeFeasibilityResult`. Bundled recipes keep their
/// deterministic makeable / almost makeable / not makeable verdict; these are
/// extra ideas alongside them.
struct RecipeSuggestion: Identifiable, Equatable {
    let id: UUID
    let name: String
    /// Required ingredients the pantry actually has.
    let availableIngredients: [String]
    /// Required ingredients the pantry doesn't have.
    let missingIngredients: [String]
    let shortInstructions: String
    /// `nil` when the model didn't give a usable estimate.
    let estimatedPreparationMinutes: Int?

    init(
        id: UUID = UUID(),
        name: String,
        availableIngredients: [String],
        missingIngredients: [String],
        shortInstructions: String,
        estimatedPreparationMinutes: Int?
    ) {
        self.id = id
        self.name = name
        self.availableIngredients = availableIngredients
        self.missingIngredients = missingIngredients
        self.shortInstructions = shortInstructions
        self.estimatedPreparationMinutes = estimatedPreparationMinutes
    }

    /// True when every ingredient the suggestion needs is in the pantry.
    /// Derived from the pantry check, not from the model.
    var usesOnlyPantryIngredients: Bool { missingIngredients.isEmpty }

    var formattedPreparationTime: String? {
        guard let estimatedPreparationMinutes else { return nil }
        return "About \(estimatedPreparationMinutes) min"
    }
}
