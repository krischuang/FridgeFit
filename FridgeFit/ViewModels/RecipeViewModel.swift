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
///
/// Also owns recipes saved from Discover: they're loaded alongside the
/// bundled ones and evaluated by the same feasibility use case. Saving and
/// removing go through `SaveOnlineRecipeUseCase` / `RemoveSavedRecipeUseCase`.
@MainActor
final class RecipeViewModel: ObservableObject {
    @Published private(set) var recipes: [Recipe] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var feasibilityResults: [UUID: RecipeFeasibilityResult] = [:]
    /// Ids of recipes in `recipes` that the user saved from Discover.
    @Published private(set) var savedRecipeIDs: Set<UUID> = []
    /// Online recipe ids currently being saved, for per-button spinners.
    @Published private(set) var savingOnlineRecipeIDs: Set<Int> = []
    /// Last save/remove failure. Separate from `errorMessage` so it never
    /// shows up as "Couldn't Load Recipes".
    @Published var savedRecipeErrorMessage: String?
    private(set) var hasLoaded = false

    private let recipeRepository: RecipeRepository
    private let evaluateFeasibilityUseCase: EvaluateRecipeFeasibilityUseCase
    private let savedRecipeRepository: SavedRecipeRepository?
    private let saveOnlineRecipeUseCase: SaveOnlineRecipeUseCase?
    private let removeSavedRecipeUseCase: RemoveSavedRecipeUseCase?

    /// - Parameter savedRecipeRepository: `nil` disables saving from
    ///   Discover (previews, tests that don't need it).
    init(
        recipeRepository: RecipeRepository = BundledRecipeRepository(),
        pantryRepository: PantryRepository = InMemoryPantryRepository(),
        savedRecipeRepository: SavedRecipeRepository? = nil
    ) {
        self.recipeRepository = recipeRepository
        self.evaluateFeasibilityUseCase = EvaluateRecipeFeasibilityUseCase(pantryRepository: pantryRepository)
        self.savedRecipeRepository = savedRecipeRepository
        self.saveOnlineRecipeUseCase = savedRecipeRepository.map { SaveOnlineRecipeUseCase(repository: $0) }
        self.removeSavedRecipeUseCase = savedRecipeRepository.map { RemoveSavedRecipeUseCase(repository: $0) }
    }

    var canSaveRecipes: Bool { saveOnlineRecipeUseCase != nil }

    /// Recipes saved from Discover, newest first.
    var savedRecipes: [Recipe] { recipes.filter { savedRecipeIDs.contains($0.id) } }

    /// FridgeFit's own bundled recipes.
    var bundledRecipes: [Recipe] { recipes.filter { !savedRecipeIDs.contains($0.id) } }

    /// Loads (or reloads) recipes, then re-evaluates feasibility for all
    /// of them. Call whenever Recipes is opened.
    func loadRecipes() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let bundled = try await recipeRepository.fetchAll()
            errorMessage = nil

            // A saved-recipes failure must not hide the bundled list.
            var saved: [Recipe] = []
            if let savedRecipeRepository {
                do {
                    saved = try await savedRecipeRepository.fetchAll()
                } catch {
                    savedRecipeErrorMessage = (error as? SaveOnlineRecipeError)?.errorDescription
                        ?? SaveOnlineRecipeError.loadFailed.errorDescription
                    saved = savedRecipes
                }
            }

            let savedIDs = Set(saved.map(\.id))
            recipes = saved + bundled.filter { !savedIDs.contains($0.id) }
            savedRecipeIDs = savedIDs
            hasLoaded = true
            await refreshFeasibility()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Loads once if nothing has been loaded yet - used by Discover so its
    /// "Saved" badges are right even before the Recipes tab is opened.
    func loadRecipesIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await loadRecipes()
    }

    /// Whether the Discover recipe with provider id `onlineRecipeID` is
    /// already on the Recipes page.
    func isSaved(onlineRecipeID: Int) -> Bool {
        savedRecipeIDs.contains(SaveOnlineRecipeUseCase.savedRecipeID(forOnlineRecipeID: onlineRecipeID))
    }

    func isSaving(onlineRecipeID: Int) -> Bool {
        savingOnlineRecipeIDs.contains(onlineRecipeID)
    }

    /// Saves a Discover recipe to the Recipes page and evaluates it against
    /// the pantry straight away.
    func saveOnlineRecipe(_ onlineRecipe: OnlineRecipe) async {
        guard let saveOnlineRecipeUseCase, !savingOnlineRecipeIDs.contains(onlineRecipe.id) else { return }
        savingOnlineRecipeIDs.insert(onlineRecipe.id)
        defer { savingOnlineRecipeIDs.remove(onlineRecipe.id) }
        savedRecipeErrorMessage = nil

        do {
            let recipe = try await saveOnlineRecipeUseCase.execute(onlineRecipe)
            recipes.removeAll { $0.id == recipe.id }
            recipes.insert(recipe, at: 0)
            savedRecipeIDs.insert(recipe.id)
            if let result = try? await evaluateFeasibilityUseCase.execute(recipe: recipe) {
                feasibilityResults[recipe.id] = result
            }
        } catch {
            savedRecipeErrorMessage = (error as? SaveOnlineRecipeError)?.errorDescription
                ?? SaveOnlineRecipeError.saveFailed.errorDescription
        }
    }

    /// Removes a recipe saved from Discover. Ignored for bundled recipes.
    func removeSavedRecipe(_ recipe: Recipe) async {
        guard let removeSavedRecipeUseCase, savedRecipeIDs.contains(recipe.id) else { return }
        savedRecipeErrorMessage = nil
        do {
            try await removeSavedRecipeUseCase.execute(id: recipe.id)
            recipes.removeAll { $0.id == recipe.id }
            savedRecipeIDs.remove(recipe.id)
            feasibilityResults[recipe.id] = nil
        } catch {
            savedRecipeErrorMessage = (error as? SaveOnlineRecipeError)?.errorDescription
                ?? SaveOnlineRecipeError.removeFailed.errorDescription
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
