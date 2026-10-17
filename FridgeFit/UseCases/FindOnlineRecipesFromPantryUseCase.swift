//
//  FindOnlineRecipesFromPantryUseCase.swift
//  FridgeFit
//

import Foundation

/// Finds online recipes that use what's in the user's pantry, honouring
/// their diet, intolerances and time limit.
///
/// Business rules:
/// - An empty pantry is an error (`.emptyPantry`), not an unfiltered search -
///   "recipes from your pantry" with nothing in it would be misleading.
/// - Pantry names are de-duplicated case-insensitively before searching.
/// - Preferences are sanitised first, so an intolerance FridgeFit cannot
///   assess is never sent as though it were being checked.
/// - **Fail-closed safety filter**: when the user has any intolerance set,
///   a recipe is dropped if it contains one, *or* if its ingredients
///   couldn't be verified (`containsIntolerances == nil`). The provider's
///   own `intolerances` filter is trusted as a first pass only.
/// - **Use it up first**: recipes that use pantry items close to expiry
///   rank first (most urgent first), and recipes that would use an expired
///   item sink - see `OnlineRecipeExpiryRanking`. Near-expiry names are also
///   sent first in the request. Otherwise results are sorted by fewest
///   missing ingredients, then most pantry ingredients used.
/// - **Hidden recipes never come back**: ids on the team blocklist
///   (`OnlineRecipeBlocklist`) or hidden by the user are removed before
///   anything else is considered, cached results included.
/// - Nothing left after filtering is `.noResults`, so the UI can explain it.
///
/// This use case is independent of the bundled-recipe feasibility engine
/// (`EvaluateRecipeFeasibilityUseCase`) and never touches bundled recipes.
/// A recipe only meets that engine once the user explicitly saves it - see
/// `SaveOnlineRecipeUseCase`.
nonisolated struct FindOnlineRecipesFromPantryUseCase {
    let recipeService: OnlineRecipeService
    let pantryRepository: PantryRepository
    var resultLimit: Int = 30
    /// Injected so expiry boundaries are testable.
    var now: () -> Date = { Date() }
    var calendar: Calendar = .current

    /// - Parameter excludedRecipeIDs: provider recipe ids that must never
    ///   be shown (team blocklist plus the user's hidden recipes).
    func execute(
        preferences: OnlineRecipePreferences,
        excluding excludedRecipeIDs: Set<Int> = []
    ) async throws -> OnlineRecipeSearchResult {
        // Sanitise before anything else: the filter that gets sent and the
        // filter that gets enforced must be the same one, and neither may
        // name an intolerance the app cannot assess.
        let effectivePreferences = preferences.sanitized()

        let pantry: [PantryItem]
        do {
            pantry = try await pantryRepository.fetchAll()
        } catch {
            throw OnlineRecipeSearchError.pantryUnavailable
        }

        let currentDate = now()
        let urgentItems = OnlineRecipeExpiryRanking.urgentPantryItems(in: pantry, now: currentDate, calendar: calendar)
        let names = OnlineRecipeExpiryRanking.requestOrder(names: Self.uniqueNames(from: pantry), urgent: urgentItems)
        guard !names.isEmpty else { throw OnlineRecipeSearchError.emptyPantry }

        let criteria = OnlineRecipeSearchCriteria(
            pantryIngredientNames: names,
            preferences: effectivePreferences,
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

        let visible = matches.filter { !excludedRecipeIDs.contains($0.id) }
        let safe = visible.filter { Self.isSafe($0.recipe, for: effectivePreferences.intolerances) }
        guard !safe.isEmpty else { throw OnlineRecipeSearchError.noResults }

        var expiryUse: [Int: OnlineRecipeExpiryUse] = [:]
        for match in safe {
            let use = OnlineRecipeExpiryRanking.expiryUse(of: match, pantry: pantry, now: currentDate, calendar: calendar)
            if use != .none { expiryUse[match.id] = use }
        }
        let sorted = OnlineRecipeExpiryRanking.ranked(safe, expiryUse: expiryUse)

        return OnlineRecipeSearchResult(
            matches: sorted,
            excludedForSafetyCount: visible.count - safe.count,
            excludedAsHiddenCount: matches.count - visible.count,
            expiryUse: expiryUse,
            urgentPantryIngredients: urgentItems,
            pantrySnapshot: pantry
        )
    }

    /// Whether `recipe` may be shown to someone avoiding `intolerances`.
    ///
    /// Unverified (`containsIntolerances == nil`) is treated as unsafe, not
    /// as clear. "We could not check" is not evidence of absence.
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
