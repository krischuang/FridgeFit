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
        let mockService = MockSubstitutionService(result: .failure(SubstitutionServiceError.suggestionFailed))
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: InMemoryPantryRepository(), cache: SubstitutionCache())

        do {
            _ = try await useCase.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))
            XCTFail("Expected provider error to propagate")
        } catch {
            XCTAssertEqual(error as? SubstitutionServiceError, .suggestionFailed)
        }
    }

    func test_execute_modelUnavailable_propagatesUnavailableReason() async {
        let recipe = creamRecipe()
        let mockService = MockSubstitutionService(
            result: .failure(SubstitutionServiceError.substitutionUnavailable(.deviceNotSupported)),
            availability: .deviceNotSupported
        )
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: InMemoryPantryRepository(), cache: SubstitutionCache())

        XCTAssertEqual(useCase.availability, .deviceNotSupported)

        do {
            _ = try await useCase.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))
            XCTFail("Expected substitutionUnavailable to propagate")
        } catch {
            XCTAssertEqual(error as? SubstitutionServiceError, .substitutionUnavailable(.deviceNotSupported))
        }
    }

    /// `async` even though nothing is awaited - see the note in
    /// `RecommendationViewModelTests`: a synchronous test method on a
    /// `@MainActor` class aborts under this project's
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting.
    func test_availability_isReadFromTheProvider() async {
        let mockService = MockSubstitutionService(availability: .modelNotReady)
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: InMemoryPantryRepository(), cache: SubstitutionCache())

        XCTAssertEqual(useCase.availability, .modelNotReady)

        // Read fresh every time: the user can turn Apple Intelligence on
        // while the recipe screen is open.
        mockService.availability = .available
        XCTAssertEqual(useCase.availability, .available)
    }

    func test_execute_cancelledProvider_propagatesCancellation() async {
        let recipe = creamRecipe()
        let mockService = MockSubstitutionService(result: .failure(CancellationError()))
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: InMemoryPantryRepository(), cache: SubstitutionCache())

        do {
            _ = try await useCase.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))
            XCTFail("Expected cancellation to propagate")
        } catch is CancellationError {
            // Expected - the use case must not convert this into a result.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    // MARK: - Irrelevant output

    /// The most likely irrelevant answer from a small on-device model, and
    /// one that looks like a bug on screen: "instead of cream, use cream".
    /// Dropped deterministically rather than trusted to the prompt.
    func test_execute_suggestionEchoingTheOriginalIngredient_isDropped() async throws {
        let recipe = creamRecipe()
        let rawSuggestions = [
            RawSubstitutionSuggestion(ingredientName: "  CREAM ", suggestedQuantity: nil, suggestedUnit: nil, confidence: nil, explanation: "Use cream.", limitations: nil),
            RawSubstitutionSuggestion(ingredientName: "Greek Yogurt", suggestedQuantity: nil, suggestedUnit: nil, confidence: nil, explanation: "Creamy enough.", limitations: nil),
        ]
        let mockService = MockSubstitutionService(result: .success(rawSuggestions))
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: InMemoryPantryRepository(), cache: SubstitutionCache())

        let result = try await useCase.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))

        XCTAssertEqual(result.map(\.ingredientName), ["Greek Yogurt"])
    }

    /// A substitute that merely *contains* the original's name is still a
    /// different ingredient - "sour cream" for "cream" is a real answer.
    func test_execute_suggestionContainingTheOriginalName_isKept() async throws {
        let recipe = creamRecipe()
        let raw = RawSubstitutionSuggestion(ingredientName: "Sour cream", suggestedQuantity: nil, suggestedUnit: nil, confidence: nil, explanation: "Tangier, similar body.", limitations: nil)
        let mockService = MockSubstitutionService(result: .success([raw]))
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: InMemoryPantryRepository(), cache: SubstitutionCache())

        let result = try await useCase.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))

        XCTAssertEqual(result.map(\.ingredientName), ["Sour cream"])
    }

    // MARK: - Dietary exclusions are enforced in code, not by the prompt

    /// The prompt asks the model to respect restrictions; this is what makes
    /// it true. A model that ignores the instruction still can't put the
    /// excluded ingredient on screen.
    func test_execute_excludedIngredient_isRejectedEvenWhenTheModelReturnsIt() async throws {
        let recipe = creamRecipe()
        let rawSuggestions = [
            RawSubstitutionSuggestion(ingredientName: "Peanut cream", suggestedQuantity: nil, suggestedUnit: nil, confidence: nil, explanation: "Rich and creamy.", limitations: nil),
            RawSubstitutionSuggestion(ingredientName: "Oat cream", suggestedQuantity: nil, suggestedUnit: nil, confidence: nil, explanation: "Neutral and creamy.", limitations: nil),
        ]
        let mockService = MockSubstitutionService(result: .success(rawSuggestions))
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: InMemoryPantryRepository(), cache: SubstitutionCache())

        let result = try await useCase.execute(
            recipe: recipe,
            targetIngredient: recipe.ingredients[0],
            feasibility: feasibility(for: recipe),
            dietaryRestrictions: ["Peanut"]
        )

        XCTAssertEqual(result.map(\.ingredientName), ["Oat cream"])
    }

    func test_execute_restrictionsArePassedToTheProvider_asWellAsEnforcedAfterwards() async throws {
        let recipe = creamRecipe()
        let mockService = MockSubstitutionService(result: .success([]))
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: InMemoryPantryRepository(), cache: SubstitutionCache())

        _ = try await useCase.execute(
            recipe: recipe,
            targetIngredient: recipe.ingredients[0],
            feasibility: feasibility(for: recipe),
            dietaryRestrictions: ["peanut"]
        )

        XCTAssertEqual(try XCTUnwrap(mockService.lastRequest).dietaryRestrictions, ["peanut"])
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
