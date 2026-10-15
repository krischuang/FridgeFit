//
//  ContentView.swift
//  FridgeFit
//
//  Created by Kai-Hsiang on 9/9/2026.
//

import SwiftUI

/// Root of the authenticated app: Pantry, Kitchen, Recipes, and Profile,
/// each in its own tab with its own navigation stack.
struct ContentView: View {
    @StateObject private var pantryViewModel: PantryViewModel
    @StateObject private var recipeViewModel: RecipeViewModel
    @StateObject private var substitutionViewModel: SubstitutionViewModel
    @StateObject private var scannerViewModel: ReceiptScannerViewModel
    @StateObject private var recipeSuggestionViewModel: RecipeSuggestionViewModel
    /// The Kitchen tab's state. Built on the *same* `pantryRepository` as
    /// every other tab, so an item added here shows up in the Pantry list
    /// and counts towards recipe feasibility with no sync step - they are
    /// two readings of one collection, not two stores.
    @StateObject private var inventoryStore: InventoryStore
    /// Shared with the remote-camera review sheet through the environment,
    /// so a confirmed ingredient reaches the same pantry as everything else.
    private let pantryRepository: PantryRepository

    init() {
        let pantryRepository = FirestorePantryRepository()
        self.pantryRepository = pantryRepository
        _pantryViewModel = StateObject(wrappedValue: PantryViewModel(pantryRepository: pantryRepository))
        _recipeViewModel = StateObject(wrappedValue: RecipeViewModel(pantryRepository: pantryRepository))
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
    }

    var body: some View {
        TabView {
            NavigationStack {
                PantryView(viewModel: pantryViewModel, scannerViewModel: scannerViewModel)
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
                    suggestionViewModel: recipeSuggestionViewModel
                )
            }
            .tabItem { Label("Recipes", systemImage: "fork.knife") }

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle") }
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
