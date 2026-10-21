//
//  RecipeViewModelSavedRecipesTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class RecipeViewModelSavedRecipesTests: XCTestCase {
    private let bundled = Recipe(
        title: "Omelette",
        summary: "Bundled.",
        ingredients: [RecipeIngredient(ingredient: Ingredient(name: "Eggs"), quantity: 2, unit: .pieces, role: .essential)],
        instructions: ["Whisk and cook."]
    )

    private func onlineRecipe(id: Int = 5) -> OnlineRecipe {
        var recipe = OnlineRecipeFixtures.recipe(id: id, title: "Garlic Chicken")
        recipe.ingredients = [
            OnlineRecipeIngredient(providerID: 1, name: "chicken", amount: 300, unit: .grams, originalUnit: "g"),
        ]
        return recipe
    }

    private func makeViewModel(
        saved: InMemorySavedRecipeRepository = InMemorySavedRecipeRepository(),
        pantry: InMemoryPantryRepository = InMemoryPantryRepository(seedItems: [
            PantryItem(ingredient: Ingredient(name: "Chicken"), quantity: 500, unit: .grams),
        ])
    ) -> RecipeViewModel {
        RecipeViewModel(
            recipeRepository: InMemoryRecipeRepository(recipes: [bundled]),
            pantryRepository: pantry,
            savedRecipeRepository: saved
        )
    }

    func test_loadRecipes_mergesSavedAndBundled_andSplitsThem() async throws {
        let existing = try SaveOnlineRecipeUseCase.recipe(from: onlineRecipe())
        let viewModel = makeViewModel(saved: InMemorySavedRecipeRepository(recipes: [existing]))

        await viewModel.loadRecipes()

        XCTAssertEqual(viewModel.savedRecipes.map(\.id), [existing.id])
        XCTAssertEqual(viewModel.bundledRecipes.map(\.id), [bundled.id])
        XCTAssertNotNil(viewModel.feasibility(for: existing), "Saved recipes get the same pantry check")
        XCTAssertTrue(viewModel.isSaved(onlineRecipeID: 5))
    }

    func test_loadRecipes_savedFailure_stillShowsBundled() async {
        let saved = InMemorySavedRecipeRepository()
        saved.failure = URLError(.notConnectedToInternet)
        let viewModel = makeViewModel(saved: saved)

        await viewModel.loadRecipes()

        XCTAssertEqual(viewModel.recipes.map(\.id), [bundled.id])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.savedRecipeLoadErrorMessage, SaveOnlineRecipeError.loadFailed.errorDescription)
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_loadRecipes_retryAfterInitialFailure_recoversSavedCollection() async throws {
        let existing = try SaveOnlineRecipeUseCase.recipe(from: onlineRecipe())
        let saved = InMemorySavedRecipeRepository(recipes: [existing])
        saved.failure = URLError(.notConnectedToInternet)
        let viewModel = makeViewModel(saved: saved)

        await viewModel.loadRecipes()
        XCTAssertNotNil(viewModel.savedRecipeLoadErrorMessage)
        XCTAssertTrue(viewModel.savedRecipes.isEmpty)

        saved.failure = nil
        await viewModel.loadRecipes()

        XCTAssertNil(viewModel.savedRecipeLoadErrorMessage)
        XCTAssertEqual(viewModel.savedRecipes.map(\.id), [existing.id])
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_loadRecipes_repeatedSavedFailure_keepsRetryState() async {
        let saved = InMemorySavedRecipeRepository()
        saved.failure = URLError(.timedOut)
        let viewModel = makeViewModel(saved: saved)

        await viewModel.loadRecipes()
        await viewModel.loadRecipes()

        XCTAssertEqual(viewModel.savedRecipeLoadErrorMessage, SaveOnlineRecipeError.loadFailed.errorDescription)
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_loadRecipes_failureAfterSuccess_preservesPreviouslyLoadedRecipes() async throws {
        let existing = try SaveOnlineRecipeUseCase.recipe(from: onlineRecipe())
        let saved = InMemorySavedRecipeRepository(recipes: [existing])
        let viewModel = makeViewModel(saved: saved)
        await viewModel.loadRecipes()

        saved.failure = URLError(.networkConnectionLost)
        await viewModel.loadRecipes()

        XCTAssertEqual(viewModel.savedRecipes.map(\.id), [existing.id])
        XCTAssertNotNil(viewModel.savedRecipeLoadErrorMessage)
    }

    func test_saveOnlineRecipe_addsToRecipes_andEvaluatesAgainstPantry() async {
        let viewModel = makeViewModel()
        await viewModel.loadRecipes()

        await viewModel.saveOnlineRecipe(onlineRecipe())

        XCTAssertTrue(viewModel.isSaved(onlineRecipeID: 5))
        XCTAssertFalse(viewModel.isSaving(onlineRecipeID: 5))
        let saved = viewModel.savedRecipes.first
        XCTAssertEqual(saved?.title, "Garlic Chicken")
        XCTAssertEqual(saved.flatMap { viewModel.feasibility(for: $0) }?.status, .makeable)
        XCTAssertNil(viewModel.savedRecipeErrorMessage)
    }

    func test_saveOnlineRecipe_failure_setsMessage_andDoesNotAdd() async {
        let saved = InMemorySavedRecipeRepository()
        let viewModel = makeViewModel(saved: saved)
        await viewModel.loadRecipes()
        saved.failure = URLError(.timedOut)

        await viewModel.saveOnlineRecipe(onlineRecipe())

        XCTAssertFalse(viewModel.isSaved(onlineRecipeID: 5))
        XCTAssertEqual(viewModel.savedRecipeErrorMessage, SaveOnlineRecipeError.saveFailed.errorDescription)
    }

    func test_removeSavedRecipe_removesIt_butNeverRemovesBundled() async {
        let viewModel = makeViewModel()
        await viewModel.loadRecipes()
        await viewModel.saveOnlineRecipe(onlineRecipe())
        let saved = viewModel.savedRecipes[0]

        await viewModel.removeSavedRecipe(saved)
        await viewModel.removeSavedRecipe(bundled)

        XCTAssertTrue(viewModel.savedRecipes.isEmpty)
        XCTAssertEqual(viewModel.recipes.map(\.id), [bundled.id])
    }

    func test_withoutSavedRepository_savingIsDisabled() async {
        let viewModel = RecipeViewModel(recipeRepository: InMemoryRecipeRepository(recipes: [bundled]))

        await viewModel.saveOnlineRecipe(onlineRecipe())

        XCTAssertFalse(viewModel.canSaveRecipes)
        XCTAssertTrue(viewModel.savedRecipes.isEmpty)
    }

    func test_loadRecipesIfNeeded_loadsOnlyOnce() async {
        let saved = InMemorySavedRecipeRepository()
        let viewModel = makeViewModel(saved: saved)

        await viewModel.loadRecipesIfNeeded()
        saved.failure = URLError(.timedOut)
        await viewModel.loadRecipesIfNeeded()

        XCTAssertNil(viewModel.savedRecipeLoadErrorMessage, "Second call must not reload")
    }
}
