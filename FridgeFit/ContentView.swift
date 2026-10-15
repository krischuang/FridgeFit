//
//  ContentView.swift
//  FridgeFit
//
//  Created by Kai-Hsiang on 9/9/2026.
//

import SwiftUI

/// Root of the authenticated app: Pantry, Recipes, Budget and Profile, each in
/// its own tab with its own navigation stack.
struct ContentView: View {
    @StateObject private var pantryViewModel: PantryViewModel
    @StateObject private var recipeViewModel: RecipeViewModel
    @StateObject private var substitutionViewModel: SubstitutionViewModel
    @StateObject private var scannerViewModel: ReceiptScannerViewModel
    @StateObject private var recipeSuggestionViewModel: RecipeSuggestionViewModel
    // FridgeFunds (budget + waste cost). @State so the same environment - and the
    // data it has loaded - sticks around while the tab view is rebuilt
    @State private var fundsEnvironment: FundsEnvironment

    init(dependencies: AppDependencies = .live()) {
        let pantryRepository = dependencies.pantryRepository

        // FridgeFunds is built first so the add form and the receipt scanner can
        // pass prices to it
        let fundsEnvironment = dependencies.makeFundsEnvironment(pantryRepository)
        _fundsEnvironment = State(initialValue: fundsEnvironment)

        _pantryViewModel = StateObject(wrappedValue: PantryViewModel(
            pantryRepository: pantryRepository,
            priceRecorder: FundsPurchasePriceRecorder(environment: fundsEnvironment)
        ))
        _recipeViewModel = StateObject(wrappedValue: RecipeViewModel(pantryRepository: pantryRepository))

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
                    suggestionViewModel: recipeSuggestionViewModel
                )
            }
            .tabItem { Label("Recipes", systemImage: "fork.knife") }

            NavigationStack {
                BudgetDashboardView(environment: fundsEnvironment)
            }
            .tabItem { Label("Budget", systemImage: "chart.pie.fill") }

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
