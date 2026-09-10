//
//  SubstitutionViewModel.swift
//  FridgeFit
//

import Combine
import Foundation

/// Presentation state for "Find Substitute" on a recipe detail screen.
///
/// A single recipe can have several unresolved ingredients at once, each
/// with its own independent "Find Substitute" button, so state is keyed
/// by `RecipeIngredient.id` rather than being one global loading/error
/// pair. Never computes or validates anything itself - that's all
/// `GetIngredientSubstitutionsUseCase`.
@MainActor
final class SubstitutionViewModel: ObservableObject {
    @Published private(set) var suggestionsByIngredient: [UUID: [SubstitutionSuggestion]] = [:]
    @Published private(set) var loadingIngredientIDs: Set<UUID> = []
    @Published private(set) var errorMessageByIngredient: [UUID: String] = [:]

    private let useCase: GetIngredientSubstitutionsUseCase

    init(useCase: GetIngredientSubstitutionsUseCase) {
        self.useCase = useCase
    }

    func findSubstitutes(for recipeIngredient: RecipeIngredient, recipe: Recipe, feasibility: RecipeFeasibilityResult) async {
        let ingredientID = recipeIngredient.id
        errorMessageByIngredient[ingredientID] = nil
        loadingIngredientIDs.insert(ingredientID)
        defer { loadingIngredientIDs.remove(ingredientID) }

        do {
            let suggestions = try await useCase.execute(recipe: recipe, targetIngredient: recipeIngredient, feasibility: feasibility)
            suggestionsByIngredient[ingredientID] = suggestions
            if suggestions.isEmpty {
                errorMessageByIngredient[ingredientID] = "No usable substitutions were found for \(recipeIngredient.ingredient.name)."
            }
        } catch {
            errorMessageByIngredient[ingredientID] = error.localizedDescription
        }
    }

    func suggestions(for recipeIngredient: RecipeIngredient) -> [SubstitutionSuggestion]? {
        suggestionsByIngredient[recipeIngredient.id]
    }

    func isLoading(for recipeIngredient: RecipeIngredient) -> Bool {
        loadingIngredientIDs.contains(recipeIngredient.id)
    }

    func errorMessage(for recipeIngredient: RecipeIngredient) -> String? {
        errorMessageByIngredient[recipeIngredient.id]
    }
}
