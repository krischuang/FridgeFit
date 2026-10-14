//
//  ContentView.swift
//  FridgeFit
//
//  Created by Kai-Hsiang on 9/9/2026.
//

import SwiftUI

/// Root of the authenticated app: Pantry, Recipes, Discover, and Profile,
/// each in its own tab with its own navigation stack.
struct ContentView: View {
    @StateObject private var pantryViewModel: PantryViewModel
    @StateObject private var recipeViewModel: RecipeViewModel
    @StateObject private var substitutionViewModel: SubstitutionViewModel
    @StateObject private var scannerViewModel: ReceiptScannerViewModel
    @StateObject private var onlineRecipeSearchViewModel: OnlineRecipeSearchViewModel

    init() {
        let pantryRepository = FirestorePantryRepository()
        _pantryViewModel = StateObject(wrappedValue: PantryViewModel(pantryRepository: pantryRepository))
        _recipeViewModel = StateObject(
            wrappedValue: RecipeViewModel(
                pantryRepository: pantryRepository,
                savedRecipeRepository: FirestoreSavedRecipeRepository()
            )
        )

        // Apple Intelligence, on-device. Degrades to an explained
        // unavailable state rather than failing the app, so it is wired
        // unconditionally - see `AppleIntelligenceAvailability`.
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
        let substitutionService: SubstitutionService = OpenRouterConfiguration.loadFromInfoPlist()
            .map { OpenRouterSubstitutionService(configuration: $0) }
            ?? UnconfiguredSubstitutionService()
        let substitutionUseCase = GetIngredientSubstitutionsUseCase(
            substitutionService: substitutionService,
            pantryRepository: pantryRepository,
            cache: SubstitutionCache()
        )
        _substitutionViewModel = StateObject(wrappedValue: SubstitutionViewModel(useCase: substitutionUseCase))

        // Online recipes (Spoonacular). Same degrade-don't-crash rule as
        // substitutions: no key -> Discover / Pantry Ideas explain it isn't
        // set up. One view model backs both the Discover tab and the Recipes
        // tab's lightbulb sheet, so they always show the same results.
        let onlineRecipeService: OnlineRecipeService = SpoonacularConfiguration.load()
            .map {
                CachingOnlineRecipeService(
                    wrapping: SpoonacularRecipeService(configuration: $0),
                    cache: OnlineRecipeCacheStore()
                )
            }
            ?? UnconfiguredOnlineRecipeService()
        _onlineRecipeSearchViewModel = StateObject(
            wrappedValue: OnlineRecipeSearchViewModel(
                useCase: FindOnlineRecipesFromPantryUseCase(
                    recipeService: onlineRecipeService,
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
            }
            .tabItem { Label("Pantry", systemImage: "cabinet") }

            NavigationStack {
                RecipeListView(
                    viewModel: recipeViewModel,
                    substitutionViewModel: substitutionViewModel,
                    ideasViewModel: onlineRecipeSearchViewModel
                )
            }
            .tabItem { Label("Recipes", systemImage: "fork.knife") }

            NavigationStack {
                DiscoverRecipesView(viewModel: onlineRecipeSearchViewModel, recipeViewModel: recipeViewModel)
            }
            .tabItem { Label("Discover", systemImage: "globe") }

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
