//
//  RecipeSuggestionViewModelEdgeCaseTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
// The basic happy path / busy / unavailable cases already live at the bottom
// of SuggestRecipesFromPantryUseCaseTests.swift. These are the extra edge
// cases on top of that.
final class RecipeSuggestionViewModelEdgeCaseTests: XCTestCase {
    private struct SomethingBroke: Error {}

    private let eggs = PantryItem(ingredient: Ingredient(name: "Egg", category: .dairy), quantity: 6, unit: .pieces)

    private func makeViewModel(
        pantry: [PantryItem],
        result: Result<[RawRecipeSuggestion], Error> = .success([]),
        availability: AppleIntelligenceAvailability = .available
    ) -> (RecipeSuggestionViewModel, MockRecipeSuggestionService) {
        let service = MockRecipeSuggestionService(result: result, availability: availability)
        let useCase = SuggestRecipesFromPantryUseCase(
            suggestionService: service,
            pantryRepository: InMemoryPantryRepository(seedItems: pantry)
        )
        return (RecipeSuggestionViewModel(useCase: useCase), service)
    }

    private func suggestion(named name: String, needs ingredients: [String]) -> RawRecipeSuggestion {
        RawRecipeSuggestion(name: name, requiredIngredients: ingredients, shortInstructions: "Just cook it.", estimatedPreparationMinutes: 10)
    }

    func test_loadSuggestions_publishesSuggestions_splitByWhatsInThePantry() async {
        let (viewModel, _) = makeViewModel(
            pantry: [eggs],
            result: .success([suggestion(named: "Omelette", needs: ["Egg", "Milk"])])
        )

        await viewModel.loadSuggestions()

        XCTAssertEqual(viewModel.suggestions.count, 1)
        // we've got eggs but no milk, so the split should say exactly that
        XCTAssertEqual(viewModel.suggestions.first?.availableIngredients, ["Egg"])
        XCTAssertEqual(viewModel.suggestions.first?.missingIngredients, ["Milk"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.hasLoadedEmptyResult)
    }

    func test_loadSuggestions_showsEmptyState_whenPantryIsEmpty() async {
        let (viewModel, service) = makeViewModel(pantry: [])

        await viewModel.loadSuggestions()

        // empty pantry isn't an error, there's just nothing to work with
        XCTAssertTrue(viewModel.hasLoadedEmptyResult)
        XCTAssertTrue(viewModel.suggestions.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(service.suggestCallCount, 0)
    }

    func test_loadSuggestions_dropsIdeas_thatDontUseAnythingFromThePantry() async {
        let (viewModel, _) = makeViewModel(
            pantry: [eggs],
            result: .success([suggestion(named: "Steak", needs: ["Beef"])])
        )

        await viewModel.loadSuggestions()

        XCTAssertTrue(viewModel.suggestions.isEmpty)
        XCTAssertTrue(viewModel.hasLoadedEmptyResult)
    }

    func test_loadSuggestions_showsGenericMessage_forUnknownErrors() async {
        let (viewModel, _) = makeViewModel(pantry: [eggs], result: .failure(SomethingBroke()))

        await viewModel.loadSuggestions()

        // random errors shouldn't leak through, the user just gets the generic one
        XCTAssertEqual(viewModel.errorMessage, RecipeSuggestionError.suggestionFailed.localizedDescription)
        XCTAssertTrue(viewModel.suggestions.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_loadSuggestions_clearsOldError_whenRetrySucceeds() async {
        let (viewModel, service) = makeViewModel(pantry: [eggs], result: .failure(SomethingBroke()))
        await viewModel.loadSuggestions()
        XCTAssertNotNil(viewModel.errorMessage)

        // second try works, so the old error should be gone
        service.result = .success([suggestion(named: "Boiled Egg", needs: ["Egg"])])
        await viewModel.loadSuggestions()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.suggestions.map(\.name), ["Boiled Egg"])
        XCTAssertEqual(service.suggestCallCount, 2)
    }
}
