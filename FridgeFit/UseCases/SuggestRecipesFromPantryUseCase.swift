//
//  SuggestRecipesFromPantryUseCase.swift
//  FridgeFit
//

import Foundation

/// Turns raw recipe ideas into `RecipeSuggestion`s the UI can trust.
///
/// The whole point of this use case is the availability split. The model is
/// asked only what a recipe *requires*; which of those the user actually has
/// is decided here by reading `PantryRepository` and matching names with
/// `Ingredient.matches(name:)` - the same rule
/// `EvaluateRecipeFeasibilityUseCase` and `AddPantryItemUseCase` use. So a
/// suggestion can never claim an ingredient is on hand when the pantry says
/// otherwise.
///
/// Deliberately additive: bundled recipes keep their deterministic
/// feasibility verdict, and nothing here touches it.
nonisolated struct SuggestRecipesFromPantryUseCase {
    private let suggestionService: RecipeSuggestionService
    private let pantryRepository: PantryRepository

    init(suggestionService: RecipeSuggestionService, pantryRepository: PantryRepository) {
        self.suggestionService = suggestionService
        self.pantryRepository = pantryRepository
    }

    var availability: AppleIntelligenceAvailability {
        suggestionService.availability
    }

    /// Generates suggestions from the current pantry.
    ///
    /// Returns an empty array when the pantry is empty or the model had no
    /// usable ideas - both are valid empty states, not errors.
    func execute() async throws -> [RecipeSuggestion] {
        let availability = suggestionService.availability
        guard availability.canScan else {
            throw RecipeSuggestionError.suggestionUnavailable(availability)
        }

        let pantryItems = try await pantryRepository.fetchAll()
        guard !pantryItems.isEmpty else { return [] }

        let rawSuggestions = try await suggestionService.suggestRecipes(from: pantryItems)
        try Task.checkCancellation()

        return rawSuggestions.compactMap { validate($0, against: pantryItems) }
    }

    /// Checks one suggestion against the pantry, or drops it if it's unusable.
    private func validate(_ raw: RawRecipeSuggestion, against pantryItems: [PantryItem]) -> RecipeSuggestion? {
        let name = raw.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let requiredIngredients = deduplicated(
            raw.requiredIngredients
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        guard !requiredIngredients.isEmpty else { return nil }

        // The pantry decides, not the model.
        let available = requiredIngredients.filter { required in
            pantryItems.contains { $0.ingredient.matches(name: required) }
        }
        let missing = requiredIngredients.filter { required in
            !pantryItems.contains { $0.ingredient.matches(name: required) }
        }

        // A suggestion that uses nothing from the pantry isn't a pantry
        // suggestion - it's just a recipe.
        guard !available.isEmpty else { return nil }

        return RecipeSuggestion(
            name: name,
            availableIngredients: available,
            missingIngredients: missing,
            shortInstructions: raw.shortInstructions.trimmingCharacters(in: .whitespacesAndNewlines),
            estimatedPreparationMinutes: raw.estimatedPreparationMinutes > 0 ? raw.estimatedPreparationMinutes : nil
        )
    }

    private func deduplicated(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.filter { seen.insert($0.lowercased()).inserted }
    }
}
