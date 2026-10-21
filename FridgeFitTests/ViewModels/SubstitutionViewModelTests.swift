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
        let mockService = MockSubstitutionService(result: .failure(SubstitutionServiceError.suggestionFailed))
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

    // MARK: - Apple Intelligence availability

    private func viewModel(
        availability: AppleIntelligenceAvailability,
        result: Result<[RawSubstitutionSuggestion], Error> = .success([])
    ) -> (SubstitutionViewModel, MockSubstitutionService) {
        let mockService = MockSubstitutionService(result: result, availability: availability)
        let useCase = GetIngredientSubstitutionsUseCase(substitutionService: mockService, pantryRepository: InMemoryPantryRepository(), cache: SubstitutionCache())
        return (SubstitutionViewModel(useCase: useCase), mockService)
    }

    /// `async` even though nothing is awaited - see the note in
    /// `RecommendationViewModelTests`: a synchronous test method on a
    /// `@MainActor` class aborts under this project's
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting.
    func test_canFindSubstitutes_followsProviderAvailability() async {
        XCTAssertTrue(viewModel(availability: .available).0.canFindSubstitutes)
        XCTAssertFalse(viewModel(availability: .deviceNotSupported).0.canFindSubstitutes)
        XCTAssertFalse(viewModel(availability: .appleIntelligenceNotEnabled).0.canFindSubstitutes)
        XCTAssertFalse(viewModel(availability: .modelNotReady).0.canFindSubstitutes)
        XCTAssertFalse(viewModel(availability: .unavailableForUnknownReason).0.canFindSubstitutes)
    }

    /// The unavailable state must be explained, and must never produce
    /// suggestions - the provider isn't even asked.
    func test_findSubstitutes_whenUnavailable_explainsAndNeverCallsTheProvider() async {
        let (recipe, ingredient) = recipeAndIngredient()
        let raw = RawSubstitutionSuggestion(ingredientName: "Milk", suggestedQuantity: nil, suggestedUnit: nil, confidence: nil, explanation: "Thins the sauce.", limitations: nil)
        let (vm, mockService) = viewModel(availability: .appleIntelligenceNotEnabled, result: .success([raw]))

        await vm.findSubstitutes(for: ingredient, recipe: recipe, feasibility: feasibility(for: recipe))

        XCTAssertEqual(mockService.requestCount, 0)
        XCTAssertNil(vm.suggestions(for: ingredient), "No suggestions may be fabricated when the model can't run")
        XCTAssertFalse(vm.isLoading(for: ingredient))
        XCTAssertEqual(
            vm.errorMessage(for: ingredient),
            SubstitutionServiceError.substitutionUnavailable(.appleIntelligenceNotEnabled).localizedDescription
        )
    }

    func test_findSubstitutes_whenAvailabilityRecovers_worksWithoutRecreatingTheViewModel() async {
        let (recipe, ingredient) = recipeAndIngredient()
        let raw = RawSubstitutionSuggestion(ingredientName: "Milk", suggestedQuantity: nil, suggestedUnit: nil, confidence: nil, explanation: "Thins the sauce.", limitations: nil)
        let (vm, mockService) = viewModel(availability: .modelNotReady, result: .success([raw]))

        await vm.findSubstitutes(for: ingredient, recipe: recipe, feasibility: feasibility(for: recipe))
        XCTAssertEqual(mockService.requestCount, 0)

        // The model finished downloading while the screen stayed open.
        mockService.availability = .available
        await vm.findSubstitutes(for: ingredient, recipe: recipe, feasibility: feasibility(for: recipe))

        XCTAssertEqual(mockService.requestCount, 1)
        XCTAssertEqual(vm.suggestions(for: ingredient)?.first?.ingredientName, "Milk")
        XCTAssertNil(vm.errorMessage(for: ingredient))
    }

    // MARK: - Cancellation

    func test_cancel_clearsLoading_andPublishesNoResultOrError() async {
        let (recipe, ingredient) = recipeAndIngredient()
        let (vm, _) = viewModel(availability: .available, result: .failure(CancellationError()))

        await vm.findSubstitutes(for: ingredient, recipe: recipe, feasibility: feasibility(for: recipe))

        XCTAssertFalse(vm.isLoading(for: ingredient))
        XCTAssertNil(vm.suggestions(for: ingredient))
        XCTAssertNil(vm.errorMessage(for: ingredient), "A cancelled request must not leave an error on screen")
    }

    func test_cancel_forAnIngredientWithNothingInFlight_isHarmless() async {
        let (_, ingredient) = recipeAndIngredient()
        let (vm, _) = viewModel(availability: .available)

        vm.cancel(for: ingredient)
        vm.cancelAll()

        XCTAssertFalse(vm.isLoading(for: ingredient))
        XCTAssertNil(vm.errorMessage(for: ingredient))
    }

    func test_cancelAll_clearsEveryIngredientsLoadingState() async {
        let recipe = Recipe(
            title: "Two Missing",
            summary: "Test fixture.",
            ingredients: [
                RecipeIngredient(ingredient: Ingredient(name: "Cream", category: .dairy), quantity: 200, unit: .milliliters, role: .essential),
                RecipeIngredient(ingredient: Ingredient(name: "Parsley", category: .produce), quantity: 1, unit: .tablespoons, role: .optional),
            ],
            instructions: ["Cook it."]
        )
        let (vm, _) = viewModel(availability: .available)

        vm.cancelAll()

        XCTAssertFalse(vm.isLoading(for: recipe.ingredients[0]))
        XCTAssertFalse(vm.isLoading(for: recipe.ingredients[1]))
    }

    // MARK: - Repeat taps

    /// The on-device model rejects concurrent requests, so a second tap
    /// while one is in flight must be ignored rather than surfaced as a
    /// "model busy" failure.
    func test_findSubstitutes_whileAlreadyLoading_isIgnored() async {
        let (recipe, ingredient) = recipeAndIngredient()
        let raw = RawSubstitutionSuggestion(ingredientName: "Milk", suggestedQuantity: nil, suggestedUnit: nil, confidence: nil, explanation: "Thins the sauce.", limitations: nil)
        let (vm, mockService) = viewModel(availability: .available, result: .success([raw]))

        async let first: Void = vm.findSubstitutes(for: ingredient, recipe: recipe, feasibility: feasibility(for: recipe))
        async let second: Void = vm.findSubstitutes(for: ingredient, recipe: recipe, feasibility: feasibility(for: recipe))
        _ = await (first, second)

        // One provider call, and the cache absorbs any repeat anyway.
        XCTAssertEqual(mockService.requestCount, 1)
        XCTAssertEqual(vm.suggestions(for: ingredient)?.first?.ingredientName, "Milk")
    }
}
