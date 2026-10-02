//
//  SuggestRecipesFromPantryUseCaseTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class SuggestRecipesFromPantryUseCaseTests: XCTestCase {
    private func pantry(_ names: [String]) -> InMemoryPantryRepository {
        InMemoryPantryRepository(seedItems: names.map {
            PantryItem(ingredient: Ingredient(name: $0, category: .other), quantity: 1, unit: .pieces)
        })
    }

    private func rawSuggestion(
        name: String = "Tomato and egg scramble",
        requiredIngredients: [String] = ["Eggs", "Tomato", "Butter"],
        instructions: String = "Beat the eggs, soften the tomato, fold together.",
        minutes: Int = 10
    ) -> RawRecipeSuggestion {
        RawRecipeSuggestion(
            name: name,
            requiredIngredients: requiredIngredients,
            shortInstructions: instructions,
            estimatedPreparationMinutes: minutes
        )
    }

    func test_suggestRecipes_mapsStructuredResultOntoSuggestions() async throws {
        let service = MockRecipeSuggestionService(result: .success([rawSuggestion()]))
        let useCase = SuggestRecipesFromPantryUseCase(
            suggestionService: service,
            pantryRepository: pantry(["Eggs", "Tomato"])
        )

        let suggestions = try await useCase.execute()

        XCTAssertEqual(suggestions.count, 1)
        let suggestion = try XCTUnwrap(suggestions.first)
        XCTAssertEqual(suggestion.name, "Tomato and egg scramble")
        XCTAssertEqual(suggestion.estimatedPreparationMinutes, 10)
        XCTAssertEqual(suggestion.formattedPreparationTime, "About 10 min")
        XCTAssertEqual(suggestion.shortInstructions, "Beat the eggs, soften the tomato, fold together.")
    }

    /// The pantry is the source of truth for availability, not the model.
    func test_suggestRecipes_splitsIngredientsUsingRealPantry() async throws {
        let service = MockRecipeSuggestionService(result: .success([rawSuggestion()]))
        let useCase = SuggestRecipesFromPantryUseCase(
            suggestionService: service,
            pantryRepository: pantry(["Eggs", "Tomato"])
        )

        let suggestions = try await useCase.execute()
        let suggestion = try XCTUnwrap(suggestions.first)

        XCTAssertEqual(suggestion.availableIngredients, ["Eggs", "Tomato"])
        XCTAssertEqual(suggestion.missingIngredients, ["Butter"])
        XCTAssertFalse(suggestion.usesOnlyPantryIngredients)
    }

    /// Even if a model implies everything is on hand, an ingredient the
    /// pantry doesn't have must land in `missingIngredients`.
    func test_suggestRecipes_marksIngredientMissing_whenPantryDisagrees() async throws {
        let service = MockRecipeSuggestionService(result: .success([
            rawSuggestion(requiredIngredients: ["Eggs", "Saffron", "Truffle"])
        ]))
        let useCase = SuggestRecipesFromPantryUseCase(
            suggestionService: service,
            pantryRepository: pantry(["Eggs"])
        )

        let suggestions = try await useCase.execute()
        let suggestion = try XCTUnwrap(suggestions.first)

        XCTAssertEqual(suggestion.availableIngredients, ["Eggs"])
        XCTAssertEqual(suggestion.missingIngredients, ["Saffron", "Truffle"])
    }

    func test_suggestRecipes_matchesIngredientNamesCaseInsensitively() async throws {
        let service = MockRecipeSuggestionService(result: .success([
            rawSuggestion(requiredIngredients: ["  eggs ", "TOMATO"])
        ]))
        let useCase = SuggestRecipesFromPantryUseCase(
            suggestionService: service,
            pantryRepository: pantry(["Eggs", "Tomato"])
        )

        let suggestions = try await useCase.execute()
        let suggestion = try XCTUnwrap(suggestions.first)

        XCTAssertTrue(suggestion.usesOnlyPantryIngredients)
        XCTAssertTrue(suggestion.missingIngredients.isEmpty)
    }

    func test_suggestRecipes_sendsRealPantryToService() async throws {
        let service = MockRecipeSuggestionService(result: .success([rawSuggestion()]))
        let useCase = SuggestRecipesFromPantryUseCase(
            suggestionService: service,
            pantryRepository: pantry(["Eggs", "Tomato"])
        )

        _ = try await useCase.execute()

        XCTAssertEqual(service.suggestCallCount, 1)
        XCTAssertEqual(service.lastPantryItems.map(\.name), ["Eggs", "Tomato"])
    }

    /// A suggestion that uses nothing from the pantry isn't a pantry idea.
    func test_suggestRecipes_dropsSuggestionsUsingNothingFromPantry() async throws {
        let service = MockRecipeSuggestionService(result: .success([
            rawSuggestion(name: "Beef wellington", requiredIngredients: ["Beef", "Pastry"]),
            rawSuggestion()
        ]))
        let useCase = SuggestRecipesFromPantryUseCase(
            suggestionService: service,
            pantryRepository: pantry(["Eggs", "Tomato"])
        )

        let suggestions = try await useCase.execute()

        XCTAssertEqual(suggestions.map(\.name), ["Tomato and egg scramble"])
    }

    func test_suggestRecipes_dropsSuggestionsWithBlankNameOrNoIngredients() async throws {
        let service = MockRecipeSuggestionService(result: .success([
            rawSuggestion(name: "   "),
            rawSuggestion(name: "Nothing at all", requiredIngredients: ["", "  "])
        ]))
        let useCase = SuggestRecipesFromPantryUseCase(
            suggestionService: service,
            pantryRepository: pantry(["Eggs"])
        )

        let suggestions = try await useCase.execute()
        XCTAssertTrue(suggestions.isEmpty)
    }

    func test_suggestRecipes_deduplicatesRequiredIngredients() async throws {
        let service = MockRecipeSuggestionService(result: .success([
            rawSuggestion(requiredIngredients: ["Eggs", "eggs", "EGGS", "Butter"])
        ]))
        let useCase = SuggestRecipesFromPantryUseCase(
            suggestionService: service,
            pantryRepository: pantry(["Eggs"])
        )

        let suggestions = try await useCase.execute()
        let suggestion = try XCTUnwrap(suggestions.first)

        XCTAssertEqual(suggestion.availableIngredients, ["Eggs"])
        XCTAssertEqual(suggestion.missingIngredients, ["Butter"])
    }

    func test_suggestRecipes_treatsZeroMinutesAsNoEstimate() async throws {
        let service = MockRecipeSuggestionService(result: .success([rawSuggestion(minutes: 0)]))
        let useCase = SuggestRecipesFromPantryUseCase(
            suggestionService: service,
            pantryRepository: pantry(["Eggs"])
        )

        let suggestions = try await useCase.execute()
        let suggestion = try XCTUnwrap(suggestions.first)

        XCTAssertNil(suggestion.estimatedPreparationMinutes)
        XCTAssertNil(suggestion.formattedPreparationTime)
    }

    func test_suggestRecipes_returnsEmpty_forEmptyPantry() async throws {
        let service = MockRecipeSuggestionService(result: .success([rawSuggestion()]))
        let useCase = SuggestRecipesFromPantryUseCase(
            suggestionService: service,
            pantryRepository: InMemoryPantryRepository()
        )

        let suggestions = try await useCase.execute()
        XCTAssertTrue(suggestions.isEmpty)
        XCTAssertEqual(service.suggestCallCount, 0, "No point asking about an empty pantry")
    }

    func test_suggestRecipes_throwsUnavailable_whenModelUnavailable() async {
        let service = MockRecipeSuggestionService(availability: .deviceNotSupported)
        let useCase = SuggestRecipesFromPantryUseCase(
            suggestionService: service,
            pantryRepository: pantry(["Eggs"])
        )

        do {
            _ = try await useCase.execute()
            XCTFail("Expected suggestionUnavailable")
        } catch let error as RecipeSuggestionError {
            XCTAssertEqual(error, .suggestionUnavailable(.deviceNotSupported))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(service.suggestCallCount, 0)
    }
}

@MainActor
final class RecipeSuggestionViewModelTests: XCTestCase {
    private func makeViewModel(
        service: MockRecipeSuggestionService,
        pantryNames: [String] = ["Eggs", "Tomato"]
    ) -> RecipeSuggestionViewModel {
        let repository = InMemoryPantryRepository(seedItems: pantryNames.map {
            PantryItem(ingredient: Ingredient(name: $0, category: .other), quantity: 1, unit: .pieces)
        })
        return RecipeSuggestionViewModel(
            useCase: SuggestRecipesFromPantryUseCase(suggestionService: service, pantryRepository: repository)
        )
    }

    func test_loadSuggestions_exposesSuggestions() async {
        let service = MockRecipeSuggestionService(result: .success([
            RawRecipeSuggestion(
                name: "Tomato and egg scramble",
                requiredIngredients: ["Eggs", "Tomato"],
                shortInstructions: "Scramble together.",
                estimatedPreparationMinutes: 8
            )
        ]))
        let viewModel = makeViewModel(service: service)

        await viewModel.loadSuggestions()

        XCTAssertEqual(viewModel.suggestions.map(\.name), ["Tomato and egg scramble"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.hasLoadedEmptyResult)
    }

    func test_loadSuggestions_reportsEmptyResult() async {
        let viewModel = makeViewModel(service: MockRecipeSuggestionService(result: .success([])))

        await viewModel.loadSuggestions()

        XCTAssertTrue(viewModel.suggestions.isEmpty)
        XCTAssertTrue(viewModel.hasLoadedEmptyResult)
        XCTAssertNil(viewModel.errorMessage)
    }

    func test_loadSuggestions_setsUserFacingError_whenServiceThrows() async {
        let viewModel = makeViewModel(
            service: MockRecipeSuggestionService(result: .failure(RecipeSuggestionError.modelBusy))
        )

        await viewModel.loadSuggestions()

        XCTAssertTrue(viewModel.suggestions.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, RecipeSuggestionError.modelBusy.localizedDescription)
    }

    func test_loadSuggestions_isBlocked_whenModelUnavailable() async {
        let service = MockRecipeSuggestionService(availability: .appleIntelligenceNotEnabled)
        let viewModel = makeViewModel(service: service)

        XCTAssertFalse(viewModel.canSuggest)
        await viewModel.loadSuggestions()

        XCTAssertEqual(service.suggestCallCount, 0)
        XCTAssertEqual(
            viewModel.errorMessage,
            RecipeSuggestionError.suggestionUnavailable(.appleIntelligenceNotEnabled).localizedDescription
        )
    }
}
