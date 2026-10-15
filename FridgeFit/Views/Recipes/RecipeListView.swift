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
    /// Drives the context-aware recommendation screen, pushed from the
    /// toolbar onto this tab's existing stack.
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
                List(viewModel.recipes) { recipe in
                    NavigationLink {
                        RecipeDetailView(recipe: recipe, viewModel: viewModel, substitutionViewModel: substitutionViewModel)
                    } label: {
                        RecipeRow(recipe: recipe, feasibility: viewModel.feasibility(for: recipe))
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await viewModel.refreshFeasibility() }
            }
        }
        .navigationTitle("Recipes")
        .toolbar {
            // A push, not a sheet: the recommendation screen leads on to
            // `RecipeDetailView`, and sharing this tab's stack is what
            // lets the back button return to the ranked list instead of
            // dismissing it.
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    RecipeRecommendationsView(
                        viewModel: recommendationViewModel,
                        recipeViewModel: viewModel,
                        substitutionViewModel: substitutionViewModel
                    )
                } label: {
                    Label("Recommended", systemImage: "sparkles")
                }
            }

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
