//
//  RecipeSuggestionService.swift
//  FridgeFit
//

import Foundation

/// Abstraction over whatever proposes recipe ideas from what's in the
/// pantry.
///
/// Returns untrusted `RawRecipeSuggestion`s. The service is told what the
/// pantry contains, but nothing it says about availability is believed -
/// `SuggestRecipesFromPantryUseCase` re-derives which ingredients are
/// actually on hand before the UI sees a suggestion.
protocol RecipeSuggestionService {
    /// Whether suggestions can be generated right now.
    var availability: IngredientRecognitionAvailability { get }

    /// Proposes recipes that lean on the given pantry items.
    ///
    /// - Throws: `IngredientRecognitionError`, never a provider-specific
    ///   error type.
    func suggestRecipes(from pantryItems: [PantryItem]) async throws -> [RawRecipeSuggestion]
}
