//
//  OnlineRecipeFeature.swift
//  FridgeFit
//

import Foundation

/// The one place that decides how much of the online-recipe feature is
/// switched on, and the only file that has to change to switch more of it on.
///
/// ## Why a gate exists at all, on top of the API key check
///
/// `SpoonacularConfiguration.load()` already returns `nil` when no key is
/// configured, and the composition root already falls back to
/// `UnconfiguredOnlineRecipeService`. That alone would keep the app offline
/// today, but it couples "is the feature approved?" to "did a key happen to
/// land in Secrets.xcconfig?" - so dropping a key in to try something else
/// would silently start spending quota against an account nobody has agreed
/// to use yet.
///
/// The two states below are therefore checked *before* any key is read.
/// While `provider` is `.disabled`, no `SpoonacularRecipeService` is ever
/// constructed, so there is no object in the process capable of making a
/// request - which is a stronger guarantee than "we decided not to call it".
///
/// ## Enabling online search later
///
/// Three independent steps, in this order:
///
/// 1. Obtain a Spoonacular key and put it in the gitignored
///    `Secrets.xcconfig` as `SPOONACULAR_API_KEY` (see
///    `Secrets.xcconfig.example`). Never commit it.
/// 2. Change `provider` below to `.enabled`.
/// 3. Rebuild. If the key is missing or malformed, Discover reports itself
///    as not configured rather than failing - no further code change is
///    needed to handle that.
///
/// Enabling saved recipes is a separate step with its own prerequisite -
/// see `savedRecipeStorage`.
nonisolated enum OnlineRecipeFeature {

    /// Whether the live provider may be constructed and called.
    enum ProviderState: Equatable {
        /// No live service is built. Discover shows an explicit
        /// "not configured" state and performs no networking.
        case disabled
        /// A live service is built *if* a valid API key is also configured.
        case enabled
    }

    /// Whether recipes saved from Discover may be written to Firestore.
    enum SavedRecipeStorageState: Equatable {
        /// No saved-recipe repository is built. The save action is not
        /// offered, and the Recipes tab shows no "Saved from Discover"
        /// section.
        ///
        /// This is the correct state until `firestore.rules` has been
        /// deployed and verified. The repository cannot establish the live
        /// Firebase project's deployment state; denied writes surface through
        /// the existing save error rather than being treated as successful.
        case disabledPendingRulesDeployment
        /// Saved recipes are read from and written to Firestore.
        case enabled
    }

    /// Current provider state.
    ///
    /// Online search is available when a local Spoonacular key is configured.
    /// Missing or malformed configuration still resolves to the explained
    /// `UnconfiguredOnlineRecipeService` path rather than issuing a request.
    static let provider: ProviderState = .enabled

    /// Current saved-recipe storage state.
    ///
    /// Saved Discover recipes use the existing per-user Firestore collection.
    /// Repository errors remain visible in the UI and never hide bundled
    /// recipes.
    static let savedRecipeStorage: SavedRecipeStorageState = .enabled

    // MARK: - Composition

    /// Builds the online recipe service for the running app.
    ///
    /// Returns `UnconfiguredOnlineRecipeService` whenever the feature is
    /// gated off *or* no valid key is configured, so callers never have to
    /// branch on availability and the Discover UI has exactly one
    /// "not set up" path to render.
    ///
    /// - Parameter configurationLoader: injected so tests can prove that a
    ///   disabled provider never even reads a key.
    static func makeOnlineRecipeService(
        state: ProviderState = provider,
        configurationLoader: () -> SpoonacularConfiguration? = { SpoonacularConfiguration.load() },
        cache: @autoclosure () -> OnlineRecipeCacheStoring = OnlineRecipeCacheStore()
    ) -> OnlineRecipeService {
        guard state == .enabled else { return UnconfiguredOnlineRecipeService() }
        guard let configuration = configurationLoader() else { return UnconfiguredOnlineRecipeService() }
        return CachingOnlineRecipeService(
            wrapping: SpoonacularRecipeService(configuration: configuration),
            cache: cache()
        )
    }

    /// Builds the saved-recipe repository, or `nil` when saving is gated off.
    ///
    /// `nil` propagates to `RecipeViewModel.canSaveRecipes == false`, which
    /// is what keeps the save action off the screen instead of letting it
    /// fail against undeployed rules.
    static func makeSavedRecipeRepository(
        state: SavedRecipeStorageState = savedRecipeStorage,
        build: () -> SavedRecipeRepository = { FirestoreSavedRecipeRepository() }
    ) -> SavedRecipeRepository? {
        guard state == .enabled else { return nil }
        return build()
    }

    /// Why saving is unavailable, for the UI to explain rather than hide
    /// silently. `nil` when saving is available.
    static func savedRecipeUnavailableExplanation(
        state: SavedRecipeStorageState = savedRecipeStorage
    ) -> String? {
        switch state {
        case .enabled:
            return nil
        case .disabledPendingRulesDeployment:
            return "Saving online recipes isn't switched on yet - its Firestore security rules still need to be deployed and checked. Everything else on this screen works."
        }
    }

    /// Why online search is unavailable, for the Discover screen to explain.
    /// `nil` when the provider is enabled (a missing key is then reported by
    /// `OnlineRecipeSearchError.notConfigured` instead).
    static func providerUnavailableExplanation(
        state: ProviderState = provider
    ) -> String? {
        switch state {
        case .enabled:
            return nil
        case .disabled:
            return "Online recipe search hasn't been set up yet. FridgeFit isn't connected to a recipe provider, so nothing here reaches the internet."
        }
    }
}
