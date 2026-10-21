//
//  OnlineRecipeSearchViewModelTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class OnlineRecipeSearchViewModelTests: XCTestCase {
    private func makeViewModel(
        result: Result<[OnlineRecipeMatch], OnlineRecipeSearchError>,
        pantry: InMemoryPantryRepository = OnlineRecipeFixtures.pantry("Garlic"),
        store: InMemoryOnlineRecipePreferencesStore = InMemoryOnlineRecipePreferencesStore()
    ) -> (OnlineRecipeSearchViewModel, MockOnlineRecipeService) {
        let service = MockOnlineRecipeService(result: result)
        let useCase = FindOnlineRecipesFromPantryUseCase(recipeService: service, pantryRepository: pantry)
        return (OnlineRecipeSearchViewModel(useCase: useCase, preferencesStore: store), service)
    }

    func test_init_loadsStoredPreferences_andDoesNotSearch() async {
        let store = InMemoryOnlineRecipePreferencesStore(preferences: OnlineRecipePreferences(diet: .vegan))
        let (viewModel, service) = makeViewModel(result: .success([]), store: store)

        XCTAssertEqual(viewModel.preferences.diet, .vegan)
        XCTAssertFalse(viewModel.hasSearched)
        XCTAssertTrue(service.receivedCriteria.isEmpty, "Searching costs API quota - only on explicit request")
    }

    func test_search_success_publishesMatches() async {
        let (viewModel, _) = makeViewModel(result: .success([OnlineRecipeFixtures.match()]))

        await viewModel.search()

        XCTAssertEqual(viewModel.matches.map(\.id), [1])
        XCTAssertTrue(viewModel.hasSearched)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func test_search_failure_setsHumanMessage_andClearsMatches() async {
        let (viewModel, _) = makeViewModel(result: .failure(.network))

        await viewModel.search()

        XCTAssertTrue(viewModel.matches.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, OnlineRecipeSearchError.network.errorDescription)
    }

    func test_search_emptyPantry_explainsWhy() async {
        let (viewModel, _) = makeViewModel(result: .success([]), pantry: InMemoryPantryRepository())

        await viewModel.search()

        XCTAssertEqual(viewModel.errorMessage, OnlineRecipeSearchError.emptyPantry.errorDescription)
    }

    func test_search_cachedResults_areFlagged() async {
        var cached = OnlineRecipeFixtures.match()
        cached.isFromCache = true
        let (viewModel, _) = makeViewModel(result: .success([cached]))

        await viewModel.search()

        XCTAssertTrue(viewModel.isShowingCachedResults)
    }

    func test_updatePreferences_persists_andClearsStaleResults() async {
        let store = InMemoryOnlineRecipePreferencesStore()
        let (viewModel, service) = makeViewModel(result: .success([OnlineRecipeFixtures.match()]), store: store)
        await viewModel.search()

        let updated = OnlineRecipePreferences(intolerances: [.dairy])
        viewModel.updatePreferences(updated)

        XCTAssertEqual(store.preferences, updated)
        XCTAssertTrue(viewModel.matches.isEmpty)
        XCTAssertFalse(viewModel.hasSearched)

        await viewModel.search()
        XCTAssertEqual(service.receivedCriteria.last?.preferences.intolerances, [.dairy])
    }

    func test_applyPreferencesAndSearch_usesUpdatedFiltersForFreshResults() async {
        let store = InMemoryOnlineRecipePreferencesStore()
        let (viewModel, service) = makeViewModel(
            result: .success([OnlineRecipeFixtures.match()]),
            store: store
        )
        let updated = OnlineRecipePreferences(
            diet: .vegetarian,
            intolerances: [.dairy],
            maxReadyTimeMinutes: 30
        )

        await viewModel.applyPreferencesAndSearch(updated)

        XCTAssertEqual(store.preferences, updated)
        XCTAssertEqual(service.receivedCriteria.count, 1)
        XCTAssertEqual(service.receivedCriteria.first?.preferences, updated)
        XCTAssertEqual(viewModel.matches.map(\.id), [1])
        XCTAssertTrue(viewModel.hasSearched)
    }
}
