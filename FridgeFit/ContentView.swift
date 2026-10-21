//
//  ContentView.swift
//  FridgeFit
//
//  Created by Kai-Hsiang on 9/9/2026.
//

import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case kitchen
    case recipes
    case home
    case discover
    case profile

    static let navigationOrder: [AppTab] = [.kitchen, .recipes, .home, .discover, .profile]
}

private enum RecipesRoute: Hashable {
    case recommendations
    case catalogue
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

    mutating func findRecipes() {
        selectedTab = .recipes
        isBrowsingRecipes = false
    }

    mutating func openDiscover() {
        selectedTab = .discover
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
    /// The Discover tab's state: online recipe search. The feature factory
    /// supplies the live cached service when a Spoonacular key is configured,
    /// and an explained unavailable service when it is not.
    @StateObject private var onlineRecipeSearchViewModel: OnlineRecipeSearchViewModel
    /// The Kitchen tab's state. Built on the *same* `pantryRepository` as
    /// every other tab, so an item added here shows up in the Pantry list
    /// and counts towards recipe feasibility with no sync step - they are
    /// two readings of one collection, not two stores.
    @StateObject private var inventoryStore: InventoryStore
    @State private var navigation = AppNavigationState()
    @State private var recipesPath: [RecipesRoute] = []
    /// Shared with the remote-camera review sheet through the environment,
    /// so a confirmed ingredient reaches the same pantry as everything else.
    private let pantryRepository: PantryRepository
    /// The money side: budget, spends and per-item prices. Built here, next
    /// to the pantry it reads, so no screen has to construct a Firestore
    /// store of its own. Reaches Profile → Impact & Budget through
    /// `\.fundsEnvironment`, the same way the pantry reaches the camera
    /// review sheet.
    private let fundsEnvironment: FundsEnvironment

    init() {
        let pantryRepository = FirestorePantryRepository()
        self.pantryRepository = pantryRepository
        self.fundsEnvironment = .firestore(pantryRepository: pantryRepository)
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
                eventRepository: FirestoreInventoryEventRepository()
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

        let substitutionService: SubstitutionService = OpenRouterConfiguration.loadFromInfoPlist()
            .map { OpenRouterSubstitutionService(configuration: $0) }
            ?? UnconfiguredSubstitutionService()
        let substitutionUseCase = GetIngredientSubstitutionsUseCase(
            substitutionService: substitutionService,
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
                preferencesStore: UserDefaultsOnlineRecipePreferencesStore()
            )
        )
    }

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            // The stack belongs to the tab. `MyKitchenView` does not open
            // one of its own, so there is exactly one navigation bar.
            Tab("My Fridge", systemImage: "refrigerator", value: AppTab.kitchen) {
                NavigationStack {
                    MyKitchenView(
                        inventory: inventoryStore,
                        scannerViewModel: scannerViewModel,
                        isPresentingSmartScan: $navigation.isPresentingSmartScan
                    )
                }
            }

            Tab("Recipes", systemImage: "book.closed", value: AppTab.recipes) {
                NavigationStack(path: $recipesPath) {
                    SavedRecipesView(
                        viewModel: recipeViewModel,
                        substitutionViewModel: substitutionViewModel,
                        onExploreDiscover: { navigation.openDiscover() },
                        onFindRecommendations: { pushRecipeRoute(.recommendations) },
                        onBrowseAllRecipes: { pushRecipeRoute(.catalogue) }
                    )
                    .navigationDestination(for: RecipesRoute.self) { route in
                        switch route {
                        case .recommendations:
                            RecipeRecommendationsView(
                                viewModel: recommendationViewModel,
                                recipeViewModel: recipeViewModel,
                                substitutionViewModel: substitutionViewModel,
                                suggestionViewModel: recipeSuggestionViewModel,
                                onBrowseAllRecipes: { pushRecipeRoute(.catalogue) }
                            )
                        case .catalogue:
                            RecipeListView(
                                viewModel: recipeViewModel,
                                substitutionViewModel: substitutionViewModel,
                                suggestionViewModel: recipeSuggestionViewModel,
                                recommendationViewModel: recommendationViewModel
                            )
                        }
                    }
                }
            }

            Tab("Home", systemImage: "house", value: AppTab.home) {
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
                        onFindRecipes: { showRecipeRoute(.recommendations) },
                        onBrowseRecipes: { showRecipeRoute(.catalogue) }
                    )
                }
            }

            // Discover is online recipes, and is deliberately its own tab
            // rather than a surface inside Recipes: Recipes is the catalogue
            // FridgeFit stands behind and checks against the pantry, and
            // mixing unsaved third-party results into it would blur that.
            // Saving is the explicit step that moves a recipe across.
            //
            // The stack belongs to the tab. `DiscoverRecipesView` opens none
            // of its own, so there is exactly one navigation bar.
            Tab("Discover", systemImage: "safari", value: AppTab.discover) {
                NavigationStack {
                    DiscoverRecipesView(
                        viewModel: onlineRecipeSearchViewModel,
                        recipeViewModel: recipeViewModel
                    )
                }
            }

            Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                NavigationStack {
                    ProfileView(
                        inventory: inventoryStore,
                        onFindRecipes: {
                            showRecipeRoute(.recommendations)
                        },
                        onOpenPantry: { navigation.openMyFridge() }
                    )
                }
                .toolbar(.visible, for: .tabBar)
            }
        }
        .tabViewStyle(.tabBarOnly)
        .tint(FridgeFitTheme.ColorToken.primary)
        .onChange(of: recipesPath) { _, path in
            navigation.isBrowsingRecipes = path.last == .catalogue
        }
        // Reaches the remote-camera review sheet, four levels down, without
        // adding a pantry parameter to ProfileView, ConnectedDevicesView and
        // RemoteCameraView - none of which have anything to do with the
        // pantry. Same repository instance as every other tab, so a confirmed
        // ingredient lands in the same place and under the same auth.
        .environment(\.pantryRepository, pantryRepository)
        // Reaches Profile → Impact & Budget without giving that screen a
        // Firestore dependency of its own. `nil` in previews and tests, in
        // which case the money cards render their unavailable state.
        .environment(\.fundsEnvironment, fundsEnvironment)
    }

    private func showRecipeRoute(_ route: RecipesRoute) {
        switch route {
        case .recommendations:
            navigation.findRecipes()
        case .catalogue:
            navigation.browseRecipes()
        }
        recipesPath = [route]
    }

    private func pushRecipeRoute(_ route: RecipesRoute) {
        guard recipesPath.last != route else { return }
        recipesPath.append(route)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
