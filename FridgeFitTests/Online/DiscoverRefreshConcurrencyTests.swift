//
//  DiscoverRefreshConcurrencyTests.swift
//  FridgeFitTests
//
//  Pantry re-checks and searches overlap in normal use: a tab change, a
//  view appearing and a pantry edit can all land within a frame. Whatever
//  the order they *finish* in, the newest answer has to be the one on
//  screen. Every test here drives completion order explicitly through
//  `GatedPantryRepository` - no sleeps.
//

import XCTest
@testable import FridgeFit

@MainActor
final class DiscoverRefreshConcurrencyTests: XCTestCase {

    private func item(_ name: String) -> PantryItem {
        PantryItem(ingredient: Ingredient(name: name, category: .other), quantity: 1, unit: .pieces)
    }

    private func viewModel(
        _ repository: GatedPantryRepository,
        _ service: MockOnlineRecipeService
    ) -> OnlineRecipeSearchViewModel {
        OnlineRecipeSearchViewModel(
            useCase: FindOnlineRecipesFromPantryUseCase(recipeService: service, pantryRepository: repository),
            preferencesStore: InMemoryOnlineRecipePreferencesStore()
        )
    }

    /// Gets the view model into "searched once, results on screen" without
    /// leaving anything parked. Returns after the search has published.
    private func searchOnce(
        _ viewModel: OnlineRecipeSearchViewModel,
        _ repository: GatedPantryRepository,
        pantry: [PantryItem]
    ) async {
        let search = Task { await viewModel.search() }
        await repository.waitForParkedFetches(1)
        await repository.release(call: 1, with: pantry)
        await search.value
    }

    // MARK: - Out-of-order completion

    func test_olderRefresh_cannotOverwriteANewerOne() async throws {
        let repository = GatedPantryRepository()
        let service = MockOnlineRecipeService(result: .success([OnlineRecipeFixtures.bakedCustard()]))
        let viewModel = viewModel(repository, service)
        await searchOnce(viewModel, repository, pantry: [item("egg")])

        // Two re-checks in flight: the first saw an egg-only pantry, the
        // second a pantry that has since gained milk and vanilla.
        let older = Task { await viewModel.refreshPantryMatch() }
        await repository.waitForParkedFetches(1)
        let newer = Task { await viewModel.refreshPantryMatch() }
        await repository.waitForParkedFetches(2)

        await repository.release(call: 3, with: [item("egg"), item("milk"), item("vanilla extract")])
        await newer.value
        XCTAssertEqual(viewModel.matches.first?.missedIngredients.map(\.name), ["brown sugar"])

        // The older re-check finishes last. Its pantry is the stale one.
        await repository.release(call: 2, with: [item("egg")])
        await older.value

        XCTAssertEqual(
            viewModel.matches.first?.missedIngredients.map(\.name),
            ["brown sugar"],
            "The re-check that started last describes the pantry best, whatever order they finished in"
        )
        let reads = await repository.fetchAllCount
        XCTAssertEqual(reads, 3, "One pantry read per request, no retries")
        XCTAssertEqual(service.receivedCriteria.count, 1, "Re-checks must never spend API quota")
    }

    /// A re-check that was already in flight when the filters changed
    /// describes neither the new filters nor a search the user can see.
    func test_refreshInFlightWhenFiltersChange_cannotRestoreTheClearedResults() async throws {
        let repository = GatedPantryRepository()
        let service = MockOnlineRecipeService(result: .success([OnlineRecipeFixtures.bakedCustard()]))
        let viewModel = viewModel(repository, service)
        await searchOnce(viewModel, repository, pantry: [item("egg")])

        let pending = Task { await viewModel.refreshPantryMatch() }
        await repository.waitForParkedFetches(1)

        viewModel.updatePreferences(OnlineRecipePreferences(diet: .vegetarian))
        await repository.release(call: 2, with: [item("egg"), item("milk")])
        await pending.value

        XCTAssertTrue(viewModel.matches.isEmpty, "Results cleared by a filter change must stay cleared")
        XCTAssertFalse(viewModel.hasSearched)
        XCTAssertEqual(service.receivedCriteria.count, 1)
    }

    /// A real search costs quota, so it always outranks a local re-check -
    /// even one that finishes while the search is still running.
    func test_refreshFinishingDuringASearch_losesToTheSearch() async throws {
        let repository = GatedPantryRepository()
        let service = MockOnlineRecipeService(result: .success([OnlineRecipeFixtures.bakedCustard()]))
        let viewModel = viewModel(repository, service)
        await searchOnce(viewModel, repository, pantry: [item("egg")])

        let pendingRefresh = Task { await viewModel.refreshPantryMatch() }
        await repository.waitForParkedFetches(1)
        let search = Task { await viewModel.search() }
        await repository.waitForParkedFetches(2)

        // The re-check completes first, with a pantry that has milk.
        await repository.release(call: 2, with: [item("egg"), item("milk")])
        await pendingRefresh.value
        XCTAssertTrue(viewModel.isLoading, "The search is still running")

        // Then the search lands, on an egg-only pantry.
        await repository.release(call: 3, with: [item("egg")])
        await search.value

        XCTAssertEqual(
            viewModel.matches.first?.missedIngredients.map(\.name),
            ["brown sugar", "milk", "vanilla extract"],
            "The search's own pantry read wins; the re-check it raced must not leak through"
        )
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(service.receivedCriteria.count, 2, "Two searches, two provider calls - and no more")
    }
}
