//
//  RecipeViewModelTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class RecipeViewModelTests: XCTestCase {
    private func singleIngredientRecipe() -> Recipe {
        Recipe(
            title: "Test Recipe",
            summary: "Test fixture.",
            ingredients: [RecipeIngredient(ingredient: Ingredient(name: "Rice", category: .grain), quantity: 300, unit: .grams, role: .essential)],
            instructions: ["Cook it."]
        )
    }

    func test_loadRecipes_populatesRecipesAndClearsErrorMessage() async {
        let recipeRepository = InMemoryRecipeRepository(recipes: [singleIngredientRecipe()])
        let viewModel = RecipeViewModel(recipeRepository: recipeRepository, pantryRepository: InMemoryPantryRepository())

        await viewModel.loadRecipes()

        XCTAssertEqual(viewModel.recipes.count, 1)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_loadRecipes_alsoEvaluatesFeasibilityForEachRecipe() async {
        let recipe = singleIngredientRecipe()
        let pantry = InMemoryPantryRepository(seedItems: [PantryItem(ingredient: Ingredient(name: "Rice", category: .grain), quantity: 500, unit: .grams)])
        let viewModel = RecipeViewModel(recipeRepository: InMemoryRecipeRepository(recipes: [recipe]), pantryRepository: pantry)

        await viewModel.loadRecipes()

        let result = viewModel.feasibility(for: recipe)
        XCTAssertEqual(result?.status, .makeable)
    }

    func test_feasibility_forUnknownRecipe_returnsNil() async {
        let viewModel = RecipeViewModel(recipeRepository: InMemoryRecipeRepository(), pantryRepository: InMemoryPantryRepository())
        await viewModel.loadRecipes()

        XCTAssertNil(viewModel.feasibility(for: singleIngredientRecipe()))
    }

    // Pantry changes must be reflected once the view model is told to
    // refresh - not before, matching the "refresh on demand" contract
    // rather than silent live syncing.
    func test_refreshFeasibility_reflectsPantryChangesSinceLastEvaluation() async {
        let recipe = singleIngredientRecipe()
        let pantryRepository = InMemoryPantryRepository(seedItems: [])
        let viewModel = RecipeViewModel(recipeRepository: InMemoryRecipeRepository(recipes: [recipe]), pantryRepository: pantryRepository)

        await viewModel.loadRecipes()
        XCTAssertEqual(viewModel.feasibility(for: recipe)?.status, .notMakeable)

        // Pantry changes "underneath" the view model, as if the user had
        // just added the ingredient from the Pantry tab.
        try? await pantryRepository.add(PantryItem(ingredient: Ingredient(name: "Rice", category: .grain), quantity: 500, unit: .grams))

        await viewModel.refreshFeasibility()

        XCTAssertEqual(viewModel.feasibility(for: recipe)?.status, .makeable)
    }

    func test_evaluateIfNeeded_evaluatesOnlyWhenNotAlreadyCached() async {
        let recipe = singleIngredientRecipe()
        let pantryRepository = InMemoryPantryRepository(seedItems: [])
        let viewModel = RecipeViewModel(recipeRepository: InMemoryRecipeRepository(recipes: [recipe]), pantryRepository: pantryRepository)

        // No loadRecipes() call - simulates opening detail before the
        // list's own evaluation has populated the cache.
        await viewModel.evaluateIfNeeded(recipe)

        XCTAssertNotNil(viewModel.feasibility(for: recipe))
    }
}
