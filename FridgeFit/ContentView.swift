//
//  ContentView.swift
//  FridgeFit
//
//  Created by Kai-Hsiang on 9/9/2026.
//

import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case home
    case kitchen
    case recipes
    case discover
    case profile
}

struct AppNavigationState: Equatable {
    var selectedTab: AppTab = .home
    var isPresentingSmartScan = false
    var isBrowsingRecipes = false

    mutating func openMyFridge() {
        selectedTab = .kitchen
    }

    mutating func openSmartScan() {
        selectedTab = .kitchen
        isPresentingSmartScan = true
    }

    mutating func browseRecipes() {
        selectedTab = .recipes
        isBrowsingRecipes = true
    }
}

/// Root of the authenticated app: Home, My Fridge, Recipes, Discover, and
/// Profile, each in its own tab with its own navigation stack. The legacy
/// Pantry management screen remains reachable from Home.
struct ContentView: View {
    @StateObject private var pantryViewModel: PantryViewModel
    @StateObject private var recipeViewModel: RecipeViewModel
    @StateObject private var substitutionViewModel: SubstitutionViewModel
    @StateObject private var scannerViewModel: ReceiptScannerViewModel
    @StateObject private var recipeSuggestionViewModel: RecipeSuggestionViewModel
    /// Context-aware recommendations. Built on the *same*
    /// `pantryRepository` and the same recipe catalogue as
    /// `recipeViewModel`, so a ranked meal and a browsed recipe are
    /// judged against one pantry and one catalogue - there is no separate
    /// sample store behind this feature.
    @StateObject private var recommendationViewModel: RecommendationViewModel
    /// The Discover tab's state: online recipe search.
    ///
    /// Built on `OnlineRecipeFeature`, which currently yields
    /// `UnconfiguredOnlineRecipeService` - no live service object exists in
    /// the process, so nothing here can reach the network. Discover renders
    /// an explicit "not set up" state instead.
    @StateObject private var onlineRecipeSearchViewModel: OnlineRecipeSearchViewModel
    /// The Kitchen tab's state. Built on the *same* `pantryRepository` as
    /// every other tab, so an item added here shows up in the Pantry list
    /// and counts towards recipe feasibility with no sync step - they are
    /// two readings of one collection, not two stores.
    @StateObject private var inventoryStore: InventoryStore
    @State private var navigation = AppNavigationState()
    /// Shared with the remote-camera review sheet through the environment,
    /// so a confirmed ingredient reaches the same pantry as everything else.
    private let pantryRepository: PantryRepository

    /// Takes its repositories from the composition root rather than building
    /// them.
    ///
    /// This initializer used to construct `FirestorePantryRepository()` and
    /// `FirestoreInventoryEventRepository()` itself, which put the choice of
    /// backend inside a `View`. Everything below is unchanged: each view model
    /// is still handed `pantryRepository` by constructor injection, so the
    /// recipe catalogue, the receipt scanner, substitutions, recommendations
    /// and Discover all read the one pantry they always did - it is now just
    /// whichever pantry `AppDependencies` selected.
    init(dependencies: AppDependencies) {
        let pantryRepository = dependencies.pantryRepository
        self.pantryRepository = pantryRepository
        let bundledRecipeRepository = BundledRecipeRepository()

        // `nil` while `OnlineRecipeFeature.savedRecipeStorage` is gated off,
        // which is the state until the saved-recipe Firestore rules are
        // deployed. A `nil` store means `canSaveRecipes` is false, so the
        // save action is never offered - rather than offered and then
        // failing with permission-denied.
        let savedRecipeRepository = OnlineRecipeFeature.makeSavedRecipeRepository()

        // One catalogue for browsing and for ranking. With saving gated off
        // this behaves exactly like `bundledRecipeRepository` alone; once
        // saved recipes are switched on they join the same ranked list with
        // no change to the recommendation engine - see
        // `CompositeRecipeRepository`.
        let recipeCatalogue = CompositeRecipeRepository(
            bundled: bundledRecipeRepository,
            savedRecipes: savedRecipeRepository
        )

        _pantryViewModel = StateObject(wrappedValue: PantryViewModel(pantryRepository: pantryRepository))
        _recipeViewModel = StateObject(
            wrappedValue: RecipeViewModel(
                recipeRepository: bundledRecipeRepository,
                pantryRepository: pantryRepository,
                savedRecipeRepository: savedRecipeRepository,
                savedRecipeUnavailableExplanation: OnlineRecipeFeature.savedRecipeUnavailableExplanation()
            )
        )
        _recommendationViewModel = StateObject(
            wrappedValue: RecommendationViewModel(
                generateUseCase: GenerateContextAwareRecommendationsUseCase(
                    recipeRepository: recipeCatalogue,
                    pantryRepository: pantryRepository
                )
            )
        )
        _inventoryStore = StateObject(
            wrappedValue: InventoryStore(
                pantryRepository: pantryRepository,
                eventRepository: dependencies.eventRepository
            )
        )

        // Apple Intelligence, on-device. Both of these degrade to an
        // explained unavailable state rather than failing the app, so they
        // are wired unconditionally - see `AppleIntelligenceAvailability`.
        //
        // Receipt scanning is two on-device stages: Vision reads the text,
        // Foundation Models interprets it. Neither sends anything off the
        // device, and the photo never reaches the language model.
        _scannerViewModel = StateObject(
            wrappedValue: ReceiptScannerViewModel(
                textRecognizer: VisionReceiptTextRecognizer(),
                interpreter: AppleReceiptIngredientInterpreter(),
                pantryRepository: pantryRepository
            )
        )
        _recipeSuggestionViewModel = StateObject(
            wrappedValue: RecipeSuggestionViewModel(
                useCase: SuggestRecipesFromPantryUseCase(
                    suggestionService: AppleRecipeSuggestionService(),
                    pantryRepository: pantryRepository
                )
            )
        )

        // Ingredient substitutions are the third on-device feature, and are
        // wired the same unconditional way for the same reason: an
        // unavailable model is an explained UI state, not a failed launch.
        // There is no API key to read any more - the recipe, the ingredient
        // and the pantry list never leave the device.
        let substitutionUseCase = GetIngredientSubstitutionsUseCase(
            substitutionService: AppleSubstitutionService(),
            pantryRepository: pantryRepository,
            cache: SubstitutionCache()
        )
        _substitutionViewModel = StateObject(wrappedValue: SubstitutionViewModel(useCase: substitutionUseCase))

        // Online recipes. Same degrade-don't-crash rule as substitutions,
        // with one extra gate in front of it: while
        // `OnlineRecipeFeature.provider` is `.disabled` this returns
        // `UnconfiguredOnlineRecipeService` without even reading an API key,
        // so Discover explains itself and performs no networking.
        _onlineRecipeSearchViewModel = StateObject(
            wrappedValue: OnlineRecipeSearchViewModel(
                useCase: FindOnlineRecipesFromPantryUseCase(
                    recipeService: OnlineRecipeFeature.makeOnlineRecipeService(),
                    pantryRepository: pantryRepository
                ),
                preferencesStore: UserDefaultsOnlineRecipePreferencesStore(),
                hiddenRecipeStore: UserDefaultsHiddenOnlineRecipeStore(),
                blockedRecipeIDs: OnlineRecipeBlocklist.bundledIDs()
            )
        )
    }

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            NavigationStack {
                HomeView(
                    inventory: inventoryStore,
                    recommendationViewModel: recommendationViewModel,
                    recipeViewModel: recipeViewModel,
                    substitutionViewModel: substitutionViewModel,
                    suggestionViewModel: recipeSuggestionViewModel,
                    pantryViewModel: pantryViewModel,
                    scannerViewModel: scannerViewModel,
                    onOpenMyFridge: { navigation.openMyFridge() },
                    onOpenSmartScan: { navigation.openSmartScan() },
                    onBrowseRecipes: { navigation.browseRecipes() }
                )
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(AppTab.home)

            // Kitchen is the spatial view of the same pantry - fridge,
            // freezer, pantry, plus expiry. Deliberately second rather than
            // first: Pantry has always been the launch tab, and this change
            // adds a view without moving the one people already use.
            //
            // The stack belongs to the tab. `MyKitchenView` does not open
            // one of its own, so there is exactly one navigation bar.
            NavigationStack {
                MyKitchenView(
                    inventory: inventoryStore,
                    scannerViewModel: scannerViewModel,
                    isPresentingSmartScan: $navigation.isPresentingSmartScan
                )
            }
            .tabItem { Label("My Fridge", systemImage: "refrigerator") }
            .tag(AppTab.kitchen)

            NavigationStack {
                RecipeRecommendationsView(
                    viewModel: recommendationViewModel,
                    recipeViewModel: recipeViewModel,
                    substitutionViewModel: substitutionViewModel,
                    suggestionViewModel: recipeSuggestionViewModel,
                    onBrowseAllRecipes: { navigation.isBrowsingRecipes = true }
                )
                .navigationDestination(isPresented: $navigation.isBrowsingRecipes) {
                    RecipeListView(
                        viewModel: recipeViewModel,
                        substitutionViewModel: substitutionViewModel,
                        suggestionViewModel: recipeSuggestionViewModel,
                        recommendationViewModel: recommendationViewModel
                    )
                }
            }
            .tabItem { Label("Recipes", systemImage: "fork.knife") }
            .tag(AppTab.recipes)

            // Discover is online recipes, and is deliberately its own tab
            // rather than a surface inside Recipes: Recipes is the catalogue
            // FridgeFit stands behind and checks against the pantry, and
            // mixing unsaved third-party results into it would blur that.
            // Saving is the explicit step that moves a recipe across.
            //
            // The stack belongs to the tab. `DiscoverRecipesView` opens none
            // of its own, so there is exactly one navigation bar.
            NavigationStack {
                DiscoverRecipesView(
                    viewModel: onlineRecipeSearchViewModel,
                    recipeViewModel: recipeViewModel
                )
            }
            .tabItem { Label("Discover", systemImage: "globe") }
            .tag(AppTab.discover)

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle") }
            .tag(AppTab.profile)
        }
        // Reaches the remote-camera review sheet, four levels down, without
        // adding a pantry parameter to ProfileView, ConnectedDevicesView and
        // RemoteCameraView - none of which have anything to do with the
        // pantry. Same repository instance as every other tab, so a confirmed
        // ingredient lands in the same place and under the same auth.
        .environment(\.pantryRepository, pantryRepository)
    }
}

#Preview {
    ContentView(
        dependencies: AppDependencies(
            backend: .swiftData,
            pantryRepository: InMemoryPantryRepository(),
            eventRepository: InMemoryInventoryEventRepository()
        )
    )
    .environmentObject(AuthViewModel())
}
