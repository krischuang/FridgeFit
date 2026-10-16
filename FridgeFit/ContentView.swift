//
//  ContentView.swift
//  FridgeFit
//
//  Created by Kai-Hsiang on 9/9/2026.
//

import SwiftUI

/// Root of the authenticated app: Pantry, Kitchen, Recipes, Discover and
/// Budget, each in its own tab with its own navigation stack.
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
    // FridgeFunds (budget + waste cost). @State so the same environment - and the
    // data it has loaded - sticks around while the tab view is rebuilt
    @State private var fundsEnvironment: FundsEnvironment
    // Profile used to be a sixth tab - iPhone only shows five before folding
    // the rest into "More", so it's a button on the Pantry tab instead
    @State private var isShowingProfile = false
    /// Shared with the remote-camera review sheet through the environment,
    /// so a confirmed ingredient reaches the same pantry as everything else.
    private let pantryRepository: PantryRepository

    init(dependencies: AppDependencies = .live()) {
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

        // FridgeFunds is built first so the add form and the receipt scanner can
        // pass prices to it
        let fundsEnvironment = dependencies.makeFundsEnvironment(pantryRepository)
        _fundsEnvironment = State(initialValue: fundsEnvironment)

        _pantryViewModel = StateObject(wrappedValue: PantryViewModel(
            pantryRepository: pantryRepository,
            priceRecorder: FundsPurchasePriceRecorder(environment: fundsEnvironment)
        ))
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
                eventRepository: dependencies.inventoryEventRepository
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
                textRecognizer: dependencies.textRecognizer,
                interpreter: dependencies.interpreter,
                pantryRepository: pantryRepository,
                priceRecorder: FundsPurchasePriceRecorder(environment: fundsEnvironment)
            )
        )
        _recipeSuggestionViewModel = StateObject(
            wrappedValue: RecipeSuggestionViewModel(
                useCase: SuggestRecipesFromPantryUseCase(
                    suggestionService: dependencies.recipeSuggestionService,
                    pantryRepository: pantryRepository
                )
            )
        )

        let substitutionUseCase = GetIngredientSubstitutionsUseCase(
            substitutionService: dependencies.substitutionService,
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
        TabView {
            NavigationStack {
                PantryView(viewModel: pantryViewModel, scannerViewModel: scannerViewModel)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                isShowingProfile = true
                            } label: {
                                Label("Profile", systemImage: "person.crop.circle")
                            }
                            .accessibilityIdentifier("profileButton")
                        }
                    }
            }
            .tabItem { Label("Pantry", systemImage: "cabinet") }

            // Kitchen is the spatial view of the same pantry - fridge,
            // freezer, pantry, plus expiry. Deliberately second rather than
            // first: Pantry has always been the launch tab, and this change
            // adds a view without moving the one people already use.
            //
            // The stack belongs to the tab. `MyKitchenView` does not open
            // one of its own, so there is exactly one navigation bar.
            NavigationStack {
                MyKitchenView(inventory: inventoryStore)
            }
            .tabItem { Label("Kitchen", systemImage: "refrigerator") }

            NavigationStack {
                RecipeListView(
                    viewModel: recipeViewModel,
                    substitutionViewModel: substitutionViewModel,
                    suggestionViewModel: recipeSuggestionViewModel,
                    recommendationViewModel: recommendationViewModel
                )
            }
            .tabItem { Label("Recipes", systemImage: "fork.knife") }

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

            NavigationStack {
                BudgetDashboardView(environment: fundsEnvironment)
            }
            .tabItem { Label("Budget", systemImage: "chart.pie.fill") }
        }
        .sheet(isPresented: $isShowingProfile) {
            NavigationStack {
                ProfileView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingProfile = false }
                        }
                    }
            }
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
    ContentView()
        .environmentObject(AuthViewModel())
}
