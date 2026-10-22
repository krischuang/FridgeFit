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

    /// Recipes the user hid on this device.
    @Published private(set) var hiddenRecipeIDs: Set<Int>
    /// How many results the last search dropped as blocked or hidden.
    @Published private(set) var excludedAsHiddenCount = 0

    private let useCase: FindOnlineRecipesFromPantryUseCase
    private let preferencesStore: OnlineRecipePreferencesStoring
    private let hiddenRecipeStore: HiddenOnlineRecipeStoring
    /// Team blocklist shipped in the bundle (`OnlineRecipeBlocklist`).
    private let blockedRecipeIDs: Set<Int>
    /// Search generation. Bumped by every `search()` and by every filter
    /// change, so a superseded search cannot publish.
    private var currentToken = 0
    /// Local re-check generation, separate from `currentToken` because a
    /// re-check must never invalidate an in-flight search - that search cost
    /// API quota. Bumping this instead lets an older re-check be dropped
    /// without touching the search it is racing.
    private var refreshGeneration = 0
    /// The provider's raw results from the last successful search, so the
    /// pantry can be re-applied without another API call.
    private var providerMatches: [OnlineRecipeMatch] = []

    init(
        useCase: FindOnlineRecipesFromPantryUseCase,
        preferencesStore: OnlineRecipePreferencesStoring,
        hiddenRecipeStore: HiddenOnlineRecipeStoring = InMemoryHiddenOnlineRecipeStore(),
        blockedRecipeIDs: Set<Int> = []
    ) {
        self.useCase = useCase
        self.preferencesStore = preferencesStore
        self.preferences = preferencesStore.load()
        self.hiddenRecipeStore = hiddenRecipeStore
        self.hiddenRecipeIDs = hiddenRecipeStore.load()
        self.blockedRecipeIDs = blockedRecipeIDs
    }

    /// Hides a recipe on this device: removed from the current results now,
    /// and excluded from every future search.
    func hide(_ match: OnlineRecipeMatch) {
        hiddenRecipeIDs.insert(match.id)
        hiddenRecipeStore.save(hiddenRecipeIDs)
        matches.removeAll { $0.id == match.id }
        expiryUseByRecipeID[match.id] = nil
        excludedAsHiddenCount += 1
    }

    /// Brings back every recipe the user hid. Takes effect on the next
    /// search. The team blocklist is not affected.
    func unhideAll() {
        hiddenRecipeIDs = []
        hiddenRecipeStore.save([])
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
            let result = try await useCase.execute(
                preferences: preferences,
                excluding: blockedRecipeIDs.union(hiddenRecipeIDs)
            )
            guard token == currentToken else { return }
            providerMatches = result.providerMatches
            apply(result)
            hasSearched = true
        } catch is CancellationError {
            return
        } catch {
            guard token == currentToken else { return }
            providerMatches = []
            matches = []
            excludedForSafetyCount = 0
            excludedAsHiddenCount = 0
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
    ///
    /// That includes the cached provider results: `diet`, `cuisine` and
    /// `maxReadyTime` are applied by the provider, so a local re-check
    /// cannot re-apply them. Keeping them would let `refreshPantryMatch()`
    /// put results fetched under the *old* filters back on screen - with
    /// `hasSearched` still false - the moment the pantry changed.
    func updatePreferences(_ newPreferences: OnlineRecipePreferences) {
        guard newPreferences != preferences else { return }
        preferences = newPreferences
        preferencesStore.save(newPreferences)
        currentToken += 1
        isLoading = false
        providerMatches = []
        matches = []
        excludedForSafetyCount = 0
        excludedAsHiddenCount = 0
        isShowingCachedResults = false
        expiryUseByRecipeID = [:]
        urgentPantryIngredients = []
        hasSearched = false
        errorMessage = nil
    }

    /// Re-checks the current results against the pantry as it is now -
    /// **no API call**. Call when Discover reappears (e.g. after the user
    /// added food in My Fridge) so "matched" / "missing", the expiry badges
    /// and the order are up to date without pressing refresh.
    ///
    /// Only the newest re-check may publish. Reading the pantry is async, so
    /// two re-checks started a moment apart can finish in either order; the
    /// generation check below means the one that started last wins, not the
    /// one that happened to finish last.
    func refreshPantryMatch() async {
        guard !isLoading, !providerMatches.isEmpty else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let token = currentToken
        do {
            let result = try await useCase.reevaluate(
                providerMatches: providerMatches,
                preferences: preferences,
                excluding: blockedRecipeIDs.union(hiddenRecipeIDs)
            )
            // Superseded by: a newer re-check, a filter change or a real
            // search (both bump `currentToken`), or a search now in flight.
            // Any of those describes the pantry or the filters better than
            // this result does.
            guard generation == refreshGeneration,
                  token == currentToken,
                  !isLoading,
                  !Task.isCancelled
            else { return }
            apply(result)
        } catch {
            // Keep what is on screen; a failed local re-check is not worth
            // replacing the list with an error.
        }
    }

    private func apply(_ result: OnlineRecipeSearchResult) {
        matches = result.matches
        excludedForSafetyCount = result.excludedForSafetyCount
        excludedAsHiddenCount = result.excludedAsHiddenCount
        isShowingCachedResults = result.isFromCache
        expiryUseByRecipeID = result.expiryUse
        urgentPantryIngredients = result.urgentPantryIngredients
    }

    /// Persists supported filters and immediately requests results that match
    /// them. Keeping this sequence in the model prevents the sheet and header
    /// from drifting into subtly different refresh behaviour.
    func applyPreferencesAndSearch(_ newPreferences: OnlineRecipePreferences) async {
        updatePreferences(newPreferences)
        await search()
    }

    /// Near-expiry / expired pantry items `match` would use.
    func expiryUse(for match: OnlineRecipeMatch) -> OnlineRecipeExpiryUse {
        expiryUseByRecipeID[match.id] ?? .none
    }
}
