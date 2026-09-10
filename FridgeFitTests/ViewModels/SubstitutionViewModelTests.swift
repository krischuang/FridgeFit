//
//  SubstitutionViewModelTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class SubstitutionViewModelTests: XCTestCase {
    private func recipeAndIngredient() -> (Recipe, RecipeIngredient) {
        let ingredient = RecipeIngredient(ingredient: Ingredient(name: "Cream", category: .dairy), quantity: 200, unit: .milliliters, role: .essential)
        let recipe = Recipe(title: "Creamy Pasta", summary: "Test fixture.", ingredients: [ingredient], instructions: ["Cook it."])
        return (recipe, ingredient)
    }

    private func feasibility(for recipe: Recipe) -> RecipeFeasibilityResult {
        RecipeFeasibilityResult(recipe: recipe, evaluatedIngredients: [], status: .notMakeable)
    }

    func test_findSubstitutes_success_populatesSuggestions_andClearsLoading() async {
        let (recipe, ingredient) = recipeAndIngredient()
        let raw = RawSubstitutionSuggestion(ingredientName: "Milk", suggestedQuantity: nil, suggestedUnit: nil, confidence: nil, explanation: "Thins the sauce.", limitations: nil)
        let mockService = MockSubstitutionService(result: .success([raw]))
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: InMemoryPantryRepository(), cache: SubstitutionCache())
        let viewModel = SubstitutionViewModel(useCase: useCase)

        await viewModel.findSubstitutes(for: ingredient, recipe: recipe, feasibility: feasibility(for: recipe))

        XCTAssertFalse(viewModel.isLoading(for: ingredient))
        XCTAssertEqual(viewModel.suggestions(for: ingredient)?.first?.ingredientName, "Milk")
        XCTAssertNil(viewModel.errorMessage(for: ingredient))
    }

    func test_findSubstitutes_failure_setsErrorMessage_forThatIngredientOnly() async {
        let (recipe, ingredient) = recipeAndIngredient()
        let mockService = MockSubstitutionService(result: .failure(SubstitutionServiceError.network))
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: InMemoryPantryRepository(), cache: SubstitutionCache())
        let viewModel = SubstitutionViewModel(useCase: useCase)

        await viewModel.findSubstitutes(for: ingredient, recipe: recipe, feasibility: feasibility(for: recipe))

        XCTAssertNotNil(viewModel.errorMessage(for: ingredient))
        XCTAssertNil(viewModel.suggestions(for: ingredient))
    }

    func test_findSubstitutes_emptyResult_setsHumanReadableErrorMessage() async {
        let (recipe, ingredient) = recipeAndIngredient()
        let mockService = MockSubstitutionService(result: .success([]))
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: InMemoryPantryRepository(), cache: SubstitutionCache())
        let viewModel = SubstitutionViewModel(useCase: useCase)

        await viewModel.findSubstitutes(for: ingredient, recipe: recipe, feasibility: feasibility(for: recipe))

        XCTAssertEqual(viewModel.suggestions(for: ingredient), [])
        XCTAssertNotNil(viewModel.errorMessage(for: ingredient))
    }

    func test_findSubstitutes_tracksStatePerIngredient_independently() async {
        let recipe = Recipe(
            title: "Two Missing",
            summary: "Test fixture.",
            ingredients: [
                RecipeIngredient(ingredient: Ingredient(name: "Cream", category: .dairy), quantity: 200, unit: .milliliters, role: .essential),
                RecipeIngredient(ingredient: Ingredient(name: "Parsley", category: .produce), quantity: 1, unit: .tablespoons, role: .optional),
            ],
            instructions: ["Cook it."]
        )
        let creamSuggestion = RawSubstitutionSuggestion(ingredientName: "Milk", suggestedQuantity: nil, suggestedUnit: nil, confidence: nil, explanation: "Thins the sauce.", limitations: nil)
        let mockService = MockSubstitutionService(result: .success([creamSuggestion]))
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: InMemoryPantryRepository(), cache: SubstitutionCache())
        let viewModel = SubstitutionViewModel(useCase: useCase)

        await viewModel.findSubstitutes(for: recipe.ingredients[0], recipe: recipe, feasibility: feasibility(for: recipe))

        XCTAssertNotNil(viewModel.suggestions(for: recipe.ingredients[0]))
        XCTAssertNil(viewModel.suggestions(for: recipe.ingredients[1]))
        XCTAssertFalse(viewModel.isLoading(for: recipe.ingredients[1]))
    }
}
