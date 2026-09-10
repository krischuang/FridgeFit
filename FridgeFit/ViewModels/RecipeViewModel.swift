//
//  RecipeViewModel.swift
//  FridgeFit
//

import Combine
import Foundation

/// Presentation state and actions for browsing recipes and checking each
/// one's feasibility against the current pantry.
///
/// Never computes feasibility itself - that's all
/// `EvaluateRecipeFeasibilityUseCase`. This just loads recipes, runs the
/// use case for each one, and caches the results by recipe id so list rows
/// and the detail screen agree on the same verdict.
@MainActor
final class RecipeViewModel: ObservableObject {
    @Published private(set) var recipes: [Recipe] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var feasibilityResults: [UUID: RecipeFeasibilityResult] = [:]

    private let recipeRepository: RecipeRepository
    private let evaluateFeasibilityUseCase: EvaluateRecipeFeasibilityUseCase

    init(
        recipeRepository: RecipeRepository = BundledRecipeRepository(),
        pantryRepository: PantryRepository = InMemoryPantryRepository()
    ) {
        self.recipeRepository = recipeRepository
        self.evaluateFeasibilityUseCase = EvaluateRecipeFeasibilityUseCase(pantryRepository: pantryRepository)
    }

    /// Loads (or reloads) recipes, then re-evaluates feasibility for all
    /// of them. Call whenever Recipes is opened.
    func loadRecipes() async {
        isLoading = true
        defer { isLoading = false }
        do {
            recipes = try await recipeRepository.fetchAll()
            errorMessage = nil
            await refreshFeasibility()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Re-evaluates every already-loaded recipe against the current
    /// pantry, without re-fetching the recipe list. Call after returning
    /// from Pantry, or on a manual pull-to-refresh.
    func refreshFeasibility() async {
        var results: [UUID: RecipeFeasibilityResult] = [:]
        for recipe in recipes {
            if let result = try? await evaluateFeasibilityUseCase.execute(recipe: recipe) {
                results[recipe.id] = result
            }
        }
        feasibilityResults = results
    }

    /// Evaluates `recipe` only if it isn't already cached - used by the
    /// detail screen as a defensive fallback in case it's opened before
    /// the list's own evaluation finishes.
    func evaluateIfNeeded(_ recipe: Recipe) async {
        guard feasibilityResults[recipe.id] == nil else { return }
        if let result = try? await evaluateFeasibilityUseCase.execute(recipe: recipe) {
            feasibilityResults[recipe.id] = result
        }
    }

    func feasibility(for recipe: Recipe) -> RecipeFeasibilityResult? {
        feasibilityResults[recipe.id]
    }
}
