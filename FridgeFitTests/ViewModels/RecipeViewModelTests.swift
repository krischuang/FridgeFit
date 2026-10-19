//
//  RecipeViewModelTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class RecipeViewModelTests: XCTestCase {
    private enum TestError: LocalizedError {
        case unavailable

        var errorDescription: String? { "Temporarily unavailable" }
    }

    private final class SequencedRecipeRepository: RecipeRepository {
        private var results: [Result<[Recipe], Error>]

        init(results: [Result<[Recipe], Error>]) {
            self.results = results
        }

        func fetchAll() async throws -> [Recipe] {
            guard !results.isEmpty else { return [] }
            return try results.removeFirst().get()
        }
    }

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

    func test_dismissingLoadErrorAlertPreservesInlineRetryState() async {
        let repository = SequencedRecipeRepository(results: [.failure(TestError.unavailable)])
        let viewModel = RecipeViewModel(recipeRepository: repository, pantryRepository: InMemoryPantryRepository())

        await viewModel.loadRecipes()
        XCTAssertTrue(viewModel.isLoadErrorAlertPresented)

        viewModel.dismissLoadErrorAlert()

        XCTAssertFalse(viewModel.isLoadErrorAlertPresented)
        XCTAssertEqual(viewModel.errorMessage, "Temporarily unavailable")
        XCTAssertTrue(viewModel.recipes.isEmpty)
    }

    func test_retryAfterTransientFailureRecoversAndClearsFailureState() async {
        let recipe = singleIngredientRecipe()
        let repository = SequencedRecipeRepository(results: [
            .failure(TestError.unavailable),
            .success([recipe]),
        ])
        let viewModel = RecipeViewModel(recipeRepository: repository, pantryRepository: InMemoryPantryRepository())

        await viewModel.loadRecipes()
        viewModel.dismissLoadErrorAlert()
        await viewModel.loadRecipes()

        XCTAssertEqual(viewModel.recipes, [recipe])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoadErrorAlertPresented)
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_successfulRetryWithNoResultsIsAGenuineEmptyState() async {
        let repository = SequencedRecipeRepository(results: [
            .failure(TestError.unavailable),
            .success([]),
        ])
        let viewModel = RecipeViewModel(recipeRepository: repository, pantryRepository: InMemoryPantryRepository())

        await viewModel.loadRecipes()
        await viewModel.loadRecipes()

        XCTAssertTrue(viewModel.recipes.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoadErrorAlertPresented)
        XCTAssertTrue(viewModel.hasLoaded)
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
