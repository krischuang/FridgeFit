//
//  RecipeListView.swift
//  FridgeFit
//

import SwiftUI

/// Lets the signed-in user browse recipes and see, at a glance, whether
/// their current pantry can make each one.
struct RecipeListView: View {
    @ObservedObject var viewModel: RecipeViewModel
    @ObservedObject var substitutionViewModel: SubstitutionViewModel
    /// Backs the lightbulb's "Pantry Ideas" sheet (Spoonacular, pantry-based).
    @ObservedObject var ideasViewModel: OnlineRecipeSearchViewModel
    @State private var isPresentingPantryIdeas = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.recipes.isEmpty {
                ProgressView("Loading Recipes\u{2026}")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.recipes.isEmpty {
                ContentUnavailableView {
                    Label("No Recipes", systemImage: "fork.knife")
                } description: {
                    Text("Check back later for recipes to cook.")
                }
            } else {
                List {
                    if !viewModel.savedRecipes.isEmpty {
                        Section {
                            ForEach(viewModel.savedRecipes) { recipe in
                                recipeLink(recipe)
                            }
                            .onDelete { offsets in
                                let targets = offsets.map { viewModel.savedRecipes[$0] }
                                Task {
                                    for recipe in targets {
                                        await viewModel.removeSavedRecipe(recipe)
                                    }
                                }
                            }
                        } header: {
                            Text("Saved from Discover")
                        } footer: {
                            Text("Recipe data via Spoonacular. Swipe left to remove.")
                        }
                    }

                    Section {
                        ForEach(viewModel.bundledRecipes) { recipe in
                            recipeLink(recipe)
                        }
                    } header: {
                        if !viewModel.savedRecipes.isEmpty {
                            Text("FridgeFit Recipes")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await viewModel.refreshFeasibility() }
            }
        }
        .navigationTitle("Recipes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingPantryIdeas = true
                } label: {
                    Label("Pantry Ideas", systemImage: "lightbulb")
                }
            }
        }
        .onAppear {
            Task { await viewModel.loadRecipes() }
        }
        .sheet(isPresented: $isPresentingPantryIdeas) {
            PantryRecipeIdeasView(viewModel: ideasViewModel, recipeViewModel: viewModel)
        }
        .alert(
            "Saved Recipes",
            isPresented: Binding(
                get: { viewModel.savedRecipeErrorMessage != nil && !isPresentingPantryIdeas },
                set: { isPresented in
                    if !isPresented { viewModel.savedRecipeErrorMessage = nil }
                }
            )
        ) {
            Button("OK") { viewModel.savedRecipeErrorMessage = nil }
        } message: {
            Text(viewModel.savedRecipeErrorMessage ?? "")
        }
        .alert(
            "Couldn't Load Recipes",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in
                    if !isPresented { viewModel.errorMessage = nil }
                }
            )
        ) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func recipeLink(_ recipe: Recipe) -> some View {
        NavigationLink {
            RecipeDetailView(recipe: recipe, viewModel: viewModel, substitutionViewModel: substitutionViewModel)
        } label: {
            RecipeRow(recipe: recipe, feasibility: viewModel.feasibility(for: recipe))
        }
    }
}

#Preview {
    let pantry = InMemoryPantryRepository(seedItems: [
        PantryItem(ingredient: Ingredient(name: "Chicken Breast", category: .meat), quantity: 500, unit: .grams),
        PantryItem(ingredient: Ingredient(name: "Pasta", category: .grain), quantity: 500, unit: .grams),
        PantryItem(ingredient: Ingredient(name: "Garlic", category: .produce), quantity: 3, unit: .pieces),
    ])
    let substitutionViewModel = SubstitutionViewModel(
        useCase: GetIngredientSubstitutionsUseCase(
            substitutionService: MockSubstitutionService(),
            pantryRepository: pantry,
            cache: SubstitutionCache()
        )
    )
    let ideasViewModel = OnlineRecipeSearchViewModel(
        useCase: FindOnlineRecipesFromPantryUseCase(
            recipeService: MockOnlineRecipeService(result: .success([])),
            pantryRepository: pantry
        ),
        preferencesStore: InMemoryOnlineRecipePreferencesStore()
    )
    NavigationStack {
        RecipeListView(
            viewModel: RecipeViewModel(pantryRepository: pantry),
            substitutionViewModel: substitutionViewModel,
            ideasViewModel: ideasViewModel
        )
    }
}
