//
//  OnlineRecipeSearchViewModel.swift
//  FridgeFit
//

import Combine
import Foundation

/// Presentation state for the Discover tab (online recipes from Spoonacular).
///
/// Kept separate from `RecipeViewModel` / `RecipeSuggestionViewModel` on
/// purpose: online results never mix into the bundled recipe list or its
/// feasibility verdicts.
///
/// Searches only run when the user asks - every call spends API quota, so
/// nothing fires on appear or on pantry edits.
@MainActor
final class OnlineRecipeSearchViewModel: ObservableObject {
    @Published private(set) var matches: [OnlineRecipeMatch] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var hasSearched = false
    @Published private(set) var excludedForSafetyCount = 0
    @Published private(set) var isShowingCachedResults = false
    @Published private(set) var preferences: OnlineRecipePreferences
    /// Per recipe id: near-expiry / expired pantry items it would use.
    @Published private(set) var expiryUseByRecipeID: [Int: OnlineRecipeExpiryUse] = [:]
    /// Pantry items the last search prioritised, most urgent first.
    @Published private(set) var urgentPantryIngredients: [UrgentIngredientUse] = []

    private let useCase: FindOnlineRecipesFromPantryUseCase
    private let preferencesStore: OnlineRecipePreferencesStoring
    private var currentToken = 0

    init(useCase: FindOnlineRecipesFromPantryUseCase, preferencesStore: OnlineRecipePreferencesStoring) {
        self.useCase = useCase
        self.preferencesStore = preferencesStore
        self.preferences = preferencesStore.load()
    }

    /// Searches using the current pantry and preferences. Ignored while a
    /// search is in flight; a superseded search can't publish its results.
    func search() async {
        guard !isLoading else { return }
        currentToken += 1
        let token = currentToken

        isLoading = true
        errorMessage = nil
        defer { if token == currentToken { isLoading = false } }

        do {
            let result = try await useCase.execute(preferences: preferences)
            guard token == currentToken else { return }
            matches = result.matches
            excludedForSafetyCount = result.excludedForSafetyCount
            isShowingCachedResults = result.isFromCache
            expiryUseByRecipeID = result.expiryUse
            urgentPantryIngredients = result.urgentPantryIngredients
            hasSearched = true
        } catch is CancellationError {
            return
        } catch {
            guard token == currentToken else { return }
            matches = []
            excludedForSafetyCount = 0
            isShowingCachedResults = false
            expiryUseByRecipeID = [:]
            urgentPantryIngredients = []
            hasSearched = true
            errorMessage = (error as? OnlineRecipeSearchError)?.errorDescription
                ?? OnlineRecipeSearchError.providerUnavailable.errorDescription
        }
    }

    /// Saves new filters. Existing results are cleared because they no
    /// longer reflect the filters - showing them would be misleading,
    /// especially after adding an intolerance.
    func updatePreferences(_ newPreferences: OnlineRecipePreferences) {
        guard newPreferences != preferences else { return }
        preferences = newPreferences
        preferencesStore.save(newPreferences)
        currentToken += 1
        isLoading = false
        matches = []
        excludedForSafetyCount = 0
        isShowingCachedResults = false
        expiryUseByRecipeID = [:]
        urgentPantryIngredients = []
        hasSearched = false
        errorMessage = nil
    }

    /// Near-expiry / expired pantry items `match` would use.
    func expiryUse(for match: OnlineRecipeMatch) -> OnlineRecipeExpiryUse {
        expiryUseByRecipeID[match.id] ?? .none
    }
}
