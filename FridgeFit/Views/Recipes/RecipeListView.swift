//
//  RecipeListView.swift
//  FridgeFit
//

import SwiftUI

/// Lets the signed-in user browse recipes and see, at a glance, whether
/// their current pantry can make each one.
struct RecipeListView: View {
    @ObservedObject var viewModel: RecipeViewModel

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
                        RecipeDetailView(recipe: recipe, viewModel: viewModel)
                    } label: {
                        RecipeRow(recipe: recipe, feasibility: viewModel.feasibility(for: recipe))
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await viewModel.refreshFeasibility() }
            }
        }
        .navigationTitle("Recipes")
        .onAppear {
            Task { await viewModel.loadRecipes() }
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
    NavigationStack {
        RecipeListView(viewModel: RecipeViewModel(pantryRepository: pantry))
    }
}
