//
//  GetIngredientSubstitutionsUseCaseTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class GetIngredientSubstitutionsUseCaseTests: XCTestCase {
    private func creamRecipe() -> Recipe {
        Recipe(
            title: "Creamy Pasta",
            summary: "Test fixture.",
            ingredients: [RecipeIngredient(ingredient: Ingredient(name: "Cream", category: .dairy), quantity: 200, unit: .milliliters, role: .essential)],
            instructions: ["Cook it."]
        )
    }

    private func feasibility(for recipe: Recipe, status: RecipeFeasibilityStatus = .notMakeable) -> RecipeFeasibilityResult {
        RecipeFeasibilityResult(recipe: recipe, evaluatedIngredients: [], status: status)
    }

    // MARK: - Request generation

    func test_execute_generatesRequest_withMissingIngredientContext() async throws {
        let recipe = creamRecipe()
        let mockService = MockSubstitutionService(result: .success([]))
        let pantry = InMemoryPantryRepository(seedItems: [
            PantryItem(ingredient: Ingredient(name: "Milk", category: .dairy), quantity: 1000, unit: .milliliters),
        ])
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: pantry, cache: SubstitutionCache())

        _ = try await useCase.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))

        let request = try XCTUnwrap(mockService.lastRequest)
        XCTAssertEqual(request.recipeID, recipe.id)
        XCTAssertEqual(request.recipeTitle, "Creamy Pasta")
        XCTAssertEqual(request.targetIngredientName, "Cream")
        XCTAssertEqual(request.requiredQuantity, 200)
        XCTAssertEqual(request.requiredUnit, .milliliters)
        XCTAssertEqual(request.role, .essential)
        XCTAssertEqual(request.pantryIngredients, [PantryIngredientSummary(name: "Milk", quantity: 1000, unit: .milliliters)])
    }

    func test_execute_generatesRequest_forInsufficientIngredient() async throws {
        let recipe = Recipe(
            title: "Rice Bowl",
            summary: "Test fixture.",
            ingredients: [RecipeIngredient(ingredient: Ingredient(name: "Rice", category: .grain), quantity: 300, unit: .grams, role: .essential)],
            instructions: ["Cook it."]
        )
        let mockService = MockSubstitutionService(result: .success([]))
        let pantry = InMemoryPantryRepository(seedItems: [PantryItem(ingredient: Ingredient(name: "Rice", category: .grain), quantity: 100, unit: .grams)])
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: pantry, cache: SubstitutionCache())

        _ = try await useCase.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe, status: .almostMakeable))

        let request = try XCTUnwrap(mockService.lastRequest)
        XCTAssertEqual(request.targetIngredientName, "Rice")
        XCTAssertEqual(request.feasibilityStatus, .almostMakeable)
    }

    // MARK: - Result shaping

    func test_execute_emptySuggestions_returnsEmptyArray() async throws {
        let recipe = creamRecipe()
        let mockService = MockSubstitutionService(result: .success([]))
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: InMemoryPantryRepository(), cache: SubstitutionCache())

        let result = try await useCase.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))

        XCTAssertTrue(result.isEmpty)
    }

    func test_execute_allSuggestionsRejected_returnsEmptyArray() async throws {
        let recipe = creamRecipe()
        let raw = RawSubstitutionSuggestion(ingredientName: "Peanut Cream", suggestedQuantity: nil, suggestedUnit: nil, confidence: nil, explanation: "Works well.", limitations: nil)
        let mockService = MockSubstitutionService(result: .success([raw]))
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: InMemoryPantryRepository(), cache: SubstitutionCache())

        let result = try await useCase.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe), dietaryRestrictions: ["peanut"])

        XCTAssertTrue(result.isEmpty)
    }

    func test_execute_duplicateSuggestions_areDeduplicated() async throws {
        let recipe = creamRecipe()
        let rawSuggestions = [
            RawSubstitutionSuggestion(ingredientName: "Greek Yogurt", suggestedQuantity: nil, suggestedUnit: nil, confidence: nil, explanation: "Creamy.", limitations: nil),
            RawSubstitutionSuggestion(ingredientName: "  greek yogurt ", suggestedQuantity: nil, suggestedUnit: nil, confidence: nil, explanation: "Also creamy.", limitations: nil),
        ]
        let mockService = MockSubstitutionService(result: .success(rawSuggestions))
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: InMemoryPantryRepository(), cache: SubstitutionCache())

        let result = try await useCase.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))

        XCTAssertEqual(result.count, 1)
    }

    func test_execute_prioritizesPantryAvailableSuggestions_first() async throws {
        let recipe = creamRecipe()
        let rawSuggestions = [
            RawSubstitutionSuggestion(ingredientName: "Coconut Milk", suggestedQuantity: nil, suggestedUnit: nil, confidence: nil, explanation: "Works if available.", limitations: nil),
            RawSubstitutionSuggestion(ingredientName: "Milk", suggestedQuantity: nil, suggestedUnit: nil, confidence: nil, explanation: "Already in your pantry.", limitations: nil),
        ]
        let mockService = MockSubstitutionService(result: .success(rawSuggestions))
        let pantry = InMemoryPantryRepository(seedItems: [PantryItem(ingredient: Ingredient(name: "Milk", category: .dairy), quantity: 1000, unit: .milliliters)])
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: pantry, cache: SubstitutionCache())

        let result = try await useCase.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))

        XCTAssertEqual(result.first?.ingredientName, "Milk")
        XCTAssertEqual(result.first?.validationStatus, .availableInPantry)
    }

    func test_execute_capsResultToThreeSuggestions() async throws {
        let recipe = creamRecipe()
        let rawSuggestions = (1...5).map {
            RawSubstitutionSuggestion(ingredientName: "Option \($0)", suggestedQuantity: nil, suggestedUnit: nil, confidence: nil, explanation: "Option \($0).", limitations: nil)
        }
        let mockService = MockSubstitutionService(result: .success(rawSuggestions))
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: InMemoryPantryRepository(), cache: SubstitutionCache())

        let result = try await useCase.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))

        XCTAssertEqual(result.count, 3)
    }

    func test_execute_providerFailure_propagatesError() async {
        let recipe = creamRecipe()
        let mockService = MockSubstitutionService(result: .failure(SubstitutionServiceError.network))
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: InMemoryPantryRepository(), cache: SubstitutionCache())

        do {
            _ = try await useCase.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))
            XCTFail("Expected network error to propagate")
        } catch {
            XCTAssertEqual(error as? SubstitutionServiceError, .network)
        }
    }

    // MARK: - Caching

    func test_execute_secondCallWithUnchangedPantry_usesCacheAndSkipsProviderCall() async throws {
        let recipe = creamRecipe()
        let raw = RawSubstitutionSuggestion(ingredientName: "Milk", suggestedQuantity: nil, suggestedUnit: nil, confidence: nil, explanation: "Works.", limitations: nil)
        let mockService = MockSubstitutionService(result: .success([raw]))
        let pantry = InMemoryPantryRepository(seedItems: [PantryItem(ingredient: Ingredient(name: "Milk", category: .dairy), quantity: 1000, unit: .milliliters)])
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: pantry, cache: SubstitutionCache())

        _ = try await useCase.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))
        _ = try await useCase.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))

        XCTAssertEqual(mockService.requestCount, 1)
    }

    func test_execute_pantryChangeBetweenCalls_invalidatesCacheAndCallsProviderAgain() async throws {
        let recipe = creamRecipe()
        let raw = RawSubstitutionSuggestion(ingredientName: "Milk", suggestedQuantity: nil, suggestedUnit: nil, confidence: nil, explanation: "Works.", limitations: nil)
        let mockService = MockSubstitutionService(result: .success([raw]))
        let pantry = InMemoryPantryRepository(seedItems: [PantryItem(ingredient: Ingredient(name: "Milk", category: .dairy), quantity: 1000, unit: .milliliters)])
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: pantry, cache: SubstitutionCache())

        _ = try await useCase.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))

        try await pantry.add(PantryItem(ingredient: Ingredient(name: "Butter", category: .dairy), quantity: 200, unit: .grams))

        _ = try await useCase.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))

        XCTAssertEqual(mockService.requestCount, 2)
    }
}
