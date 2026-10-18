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
    @ObservedObject var suggestionViewModel: RecipeSuggestionViewModel
    /// Kept shared with the Recipes tab's recommendation root so catalogue
    /// navigation never creates a second recommendation session.
    @ObservedObject var recommendationViewModel: RecommendationViewModel
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
                // Two sections only when there is something saved from
                // Discover. With saving gated off `savedRecipes` is always
                // empty, so this renders as the single unheaded list it
                // always has - the section split appears the first time it
                // means something.
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
                            Text("Recipe data via Spoonacular. Checked against your pantry like any other recipe. Swipe left to remove.")
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
            PantryRecipeIdeasView(viewModel: suggestionViewModel)
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
        // Saved-recipe problems are reported separately so a Firestore
        // failure never shows up as "Couldn't Load Recipes". Gated on
        // `errorMessage == nil` to give the two alerts a deterministic
        // precedence rather than letting both bindings go true at once.
        .alert(
            "Saved Recipes",
            isPresented: Binding(
                get: { viewModel.savedRecipeErrorMessage != nil && viewModel.errorMessage == nil },
                set: { isPresented in
                    if !isPresented { viewModel.savedRecipeErrorMessage = nil }
                }
            )
        ) {
            Button("OK") { viewModel.savedRecipeErrorMessage = nil }
        } message: {
            Text(viewModel.savedRecipeErrorMessage ?? "")
        }
    }

    /// One row, pushing the existing detail screen. Shared by both sections
    /// so a saved recipe and a bundled one are presented identically - same
    /// detail view, same feasibility verdict, same substitutions.
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
    let suggestionViewModel = RecipeSuggestionViewModel(
        useCase: SuggestRecipesFromPantryUseCase(
            suggestionService: MockRecipeSuggestionService(),
            pantryRepository: pantry
        )
    )
    let recipes = BundledRecipeRepository()
    NavigationStack {
        RecipeListView(
            viewModel: RecipeViewModel(recipeRepository: recipes, pantryRepository: pantry),
            substitutionViewModel: substitutionViewModel,
            suggestionViewModel: suggestionViewModel,
            recommendationViewModel: RecommendationViewModel(
                generateUseCase: GenerateContextAwareRecommendationsUseCase(
                    recipeRepository: recipes,
                    pantryRepository: pantry
                )
            )
        )
    }
}
