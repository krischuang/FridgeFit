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
/// ## What fires on its own, and what does not
///
/// **Searches** only run when the user asks - every call spends API quota.
/// Nothing here starts one on appear or on a pantry edit.
///
/// **Local re-checks** (`refreshPantryMatch`) do run on their own, because
/// they cost no quota: they re-apply the pantry to the results already in
/// hand. They are driven through `discoverDidAppear()`, `pantryDidChange()`
/// and `discoverDidDisappear()` rather than called directly, so the model
/// decides when the work is worth doing:
///
/// - while Discover is not the visible tab, a pantry edit is remembered and
///   nothing is recomputed for a screen nobody is looking at,
/// - arriving on Discover always re-checks against the pantry as it is now,
/// - bursts (a tab change plus the view appearing, or a receipt scan adding
///   twenty items) coalesce into a single pantry read.
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
    /// Whether Discover is the visible tab. Pantry edits made elsewhere are
    /// remembered rather than reconciled - see the type's note.
    private var isDiscoverVisible = false
    /// The coalesced re-check waiting to run. Replacing it cancels the one
    /// it replaces, which is what collapses a burst into a single read.
    ///
    /// Readable (not writable) outside the type only so tests can await the
    /// queued work rather than poll for it; nothing in the app reads it.
    private(set) var pendingPantryRefresh: Task<Void, Never>?
    /// How long a re-check waits for the burst it belongs to to finish.
    /// Injected so tests can collapse the window to nothing and stay
    /// deterministic instead of sleeping.
    private let pantryRefreshDelay: @Sendable () async -> Void

    init(
        useCase: FindOnlineRecipesFromPantryUseCase,
        preferencesStore: OnlineRecipePreferencesStoring,
        hiddenRecipeStore: HiddenOnlineRecipeStoring = InMemoryHiddenOnlineRecipeStore(),
        blockedRecipeIDs: Set<Int> = [],
        pantryRefreshDelay: @escaping @Sendable () async -> Void = {
            try? await Task.sleep(for: .milliseconds(250))
        }
    ) {
        self.useCase = useCase
        self.preferencesStore = preferencesStore
        self.preferences = preferencesStore.load()
        self.hiddenRecipeStore = hiddenRecipeStore
        self.hiddenRecipeIDs = hiddenRecipeStore.load()
        self.blockedRecipeIDs = blockedRecipeIDs
        self.pantryRefreshDelay = pantryRefreshDelay
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
    /// re-check or search - so a pantry change or returning to Discover is
    /// enough, no API call needed. The team blocklist is not affected.
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
        pendingPantryRefresh?.cancel()
        pendingPantryRefresh = nil
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

    // MARK: - Pantry-driven re-checks

    /// Discover became the visible tab, or one of its screens appeared.
    /// Queues a coalesced re-check, so arriving from My Fridge always shows
    /// the pantry as it is now - and so the tab change and the view's own
    /// `onAppear`, which land together, cost one pantry read rather than two.
    func discoverDidAppear() {
        isDiscoverVisible = true
        schedulePantryRefresh()
    }

    /// Discover is no longer the visible tab. Anything already queued is
    /// dropped and later pantry edits are ignored until the user comes back.
    ///
    /// Driven by the tab, not by `onDisappear`: pushing a recipe detail makes
    /// the list disappear while Discover is still what the user is looking
    /// at, and that detail has to keep updating.
    func discoverDidDisappear() {
        isDiscoverVisible = false
        pendingPantryRefresh?.cancel()
        pendingPantryRefresh = nil
    }

    /// The pantry changed. Only re-checks while Discover is visible; the
    /// next `discoverDidAppear()` picks up anything missed, reading the
    /// pantry once however many edits happened in between.
    func pantryDidChange() {
        guard isDiscoverVisible else { return }
        schedulePantryRefresh()
    }

    /// Replaces any queued re-check with a new one. The cancellation is the
    /// coalescing: every call in a burst retires its predecessor, so only
    /// the last one survives the delay and reads the pantry.
    private func schedulePantryRefresh() {
        guard !providerMatches.isEmpty else { return }
        pendingPantryRefresh?.cancel()
        pendingPantryRefresh = Task { [weak self, pantryRefreshDelay] in
            await pantryRefreshDelay()
            guard !Task.isCancelled else { return }
            await self?.refreshPantryMatch()
        }
    }

    /// Re-checks the current results against the pantry as it is now -
    /// **no API call**. Prefer `discoverDidAppear()` / `pantryDidChange()`,
    /// which coalesce; this is the immediate form they call.
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
