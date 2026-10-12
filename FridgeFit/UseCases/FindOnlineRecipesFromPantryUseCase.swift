//
//  FindOnlineRecipesFromPantryUseCase.swift
//  FridgeFit
//

import Foundation

/// Finds online (Spoonacular) recipes that use what's in the user's pantry,
/// honouring their diet, intolerances and time limit.
///
/// Business rules:
/// - An empty pantry is an error (`.emptyPantry`), not an unfiltered search -
///   "recipes from your pantry" with nothing in it would be misleading.
/// - Pantry names are de-duplicated case-insensitively before searching.
/// - **Fail-closed safety filter**: when the user has any intolerance set,
///   a recipe is dropped if it contains one, *or* if its ingredients
///   couldn't be verified (`containsIntolerances == nil`). The provider's
///   own `intolerances` filter is trusted as a first pass only.
/// - Results are sorted by fewest missing ingredients, then most pantry
///   ingredients used.
/// - Nothing left after filtering is `.noResults`, so the UI can explain it.
///
/// This use case is independent of the bundled-recipe feasibility engine
/// (`EvaluateRecipeFeasibilityUseCase`) and never touches bundled recipes.
struct FindOnlineRecipesFromPantryUseCase {
    let recipeService: OnlineRecipeService
    let pantryRepository: PantryRepository
    var resultLimit: Int = 30

    func execute(preferences: OnlineRecipePreferences) async throws -> OnlineRecipeSearchResult {
        let pantry: [PantryItem]
        do {
            pantry = try await pantryRepository.fetchAll()
        } catch {
            throw OnlineRecipeSearchError.pantryUnavailable
        }

        let names = Self.uniqueNames(from: pantry)
        guard !names.isEmpty else { throw OnlineRecipeSearchError.emptyPantry }

        let criteria = OnlineRecipeSearchCriteria(
            pantryIngredientNames: names,
            preferences: preferences,
            resultLimit: resultLimit
        )

        let matches: [OnlineRecipeMatch]
        do {
            matches = try await recipeService.searchRecipes(matching: criteria)
        } catch let error as OnlineRecipeSearchError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OnlineRecipeSearchError.providerUnavailable
        }

        let safe = matches.filter { Self.isSafe($0.recipe, for: preferences.intolerances) }
        guard !safe.isEmpty else { throw OnlineRecipeSearchError.noResults }

        let sorted = safe.sorted { lhs, rhs in
            if lhs.missedIngredients.count != rhs.missedIngredients.count {
                return lhs.missedIngredients.count < rhs.missedIngredients.count
            }
            return lhs.usedIngredientNames.count > rhs.usedIngredientNames.count
        }
        return OnlineRecipeSearchResult(matches: sorted, excludedForSafetyCount: matches.count - safe.count)
    }

    /// Whether `recipe` may be shown to someone avoiding `intolerances`.
    static func isSafe(_ recipe: OnlineRecipe, for intolerances: Set<FoodIntolerance>) -> Bool {
        guard !intolerances.isEmpty else { return true }
        guard let contained = recipe.containsIntolerances else { return false }
        return contained.isDisjoint(with: intolerances)
    }

    static func uniqueNames(from pantry: [PantryItem]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in pantry {
            let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !trimmed.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }
}
