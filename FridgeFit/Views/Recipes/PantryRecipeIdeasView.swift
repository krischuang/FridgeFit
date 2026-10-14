//
//  PantryRecipeIdeasView.swift
//  FridgeFit
//

import SwiftUI

/// Recipe ideas from Spoonacular based on what's in the pantry, presented as
/// a sheet from the Recipes tab's lightbulb button.
///
/// Reuses the Discover screen and its `OnlineRecipeSearchViewModel`, so the
/// sheet and the Discover tab always agree. Searches automatically the first
/// time it opens; after that, results stay until the user searches again or
/// changes filters. Sits alongside the bundled recipe list rather than inside
/// it - these are online ideas, never mixed into bundled feasibility.
struct PantryRecipeIdeasView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: OnlineRecipeSearchViewModel
    /// Lets the user save an idea to the Recipes page.
    @ObservedObject var recipeViewModel: RecipeViewModel

    var body: some View {
        NavigationStack {
            DiscoverRecipesView(viewModel: viewModel, recipeViewModel: recipeViewModel, title: "Pantry Ideas", searchesOnAppear: true)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

#Preview {
    let pantry = InMemoryPantryRepository(seedItems: [
        PantryItem(ingredient: Ingredient(name: "Eggs", category: .other), quantity: 6, unit: .pieces),
        PantryItem(ingredient: Ingredient(name: "Tomato", category: .produce), quantity: 3, unit: .pieces)
    ])
    let match = OnlineRecipeMatch(
        recipe: OnlineRecipe(
            id: 1,
            title: "Tomato and Egg Scramble",
            imageURL: nil,
            readyInMinutes: 10,
            servings: 2,
            summary: "A quick scramble.",
            sourceName: nil,
            sourceURL: nil,
            healthScore: nil,
            diets: [],
            ingredients: [],
            steps: ["Beat the eggs.", "Cook with the tomato until just set."],
            containsIntolerances: []
        ),
        usedIngredientNames: ["eggs", "tomato"],
        missedIngredients: []
    )
    let useCase = FindOnlineRecipesFromPantryUseCase(
        recipeService: MockOnlineRecipeService(result: .success([match])),
        pantryRepository: pantry
    )
    return PantryRecipeIdeasView(
        viewModel: OnlineRecipeSearchViewModel(useCase: useCase, preferencesStore: InMemoryOnlineRecipePreferencesStore()),
        recipeViewModel: RecipeViewModel(pantryRepository: pantry, savedRecipeRepository: InMemorySavedRecipeRepository())
    )
}
