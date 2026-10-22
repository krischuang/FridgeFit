//
//  DiscoverRefreshTriggerTests.swift
//  FridgeFitTests
//
//  A local re-check costs no API quota, but it is not free: it reads the
//  pantry and reconciles every result. These tests pin down when that work
//  happens - only for a screen someone is looking at, and once per burst.
//

import XCTest
@testable import FridgeFit

@MainActor
final class DiscoverRefreshTriggerTests: XCTestCase {

    private func item(_ name: String) -> PantryItem {
        PantryItem(ingredient: Ingredient(name: name, category: .other), quantity: 1, unit: .pieces)
    }

    /// The debounce window, held open by the test rather than by a clock.
    private let gate = RefreshDelayGate()

    private func makeViewModel(
        _ pantry: CountingPantryRepository,
        _ service: MockOnlineRecipeService,
        hiddenRecipeStore: HiddenOnlineRecipeStoring = InMemoryHiddenOnlineRecipeStore()
    ) -> OnlineRecipeSearchViewModel {
        let gate = gate
        return OnlineRecipeSearchViewModel(
            useCase: FindOnlineRecipesFromPantryUseCase(recipeService: service, pantryRepository: pantry),
            preferencesStore: InMemoryOnlineRecipePreferencesStore(),
            hiddenRecipeStore: hiddenRecipeStore,
            pantryRefreshDelay: { await gate.wait() }
        )
    }

    /// Closes the burst: lets the queued re-checks through and waits for the
    /// surviving one. Nothing is polled - the model exposes the task, so the
    /// test awaits exactly the work it triggered.
    private func drain(_ viewModel: OnlineRecipeSearchViewModel) async {
        await gate.open()
        await viewModel.pendingPantryRefresh?.value
        await gate.close()
    }

    // MARK: - Gating

    func test_pantryChangesWhileDiscoverIsAway_doNoWork_thenApplyOnArrival() async throws {
        let pantry = CountingPantryRepository(seedItems: [item("egg")])
        let service = MockOnlineRecipeService(result: .success([OnlineRecipeFixtures.bakedCustard()]))
        let viewModel = makeViewModel(pantry, service)

        await viewModel.search()
        viewModel.discoverDidAppear()
        await drain(viewModel)
        let readsOnArrival = pantry.fetchAllCount

        // The user leaves Discover and reorganises My Fridge.
        viewModel.discoverDidDisappear()
        try await pantry.add(item("milk"))
        viewModel.pantryDidChange()
        try await pantry.add(item("vanilla extract"))
        viewModel.pantryDidChange()
        await drain(viewModel)

        XCTAssertEqual(
            pantry.fetchAllCount,
            readsOnArrival,
            "Nothing should be recomputed for a tab the user is not looking at"
        )
        XCTAssertEqual(
            viewModel.matches.first?.missedIngredients.map(\.name),
            ["brown sugar", "milk", "vanilla extract"],
            "The stale answer is still on screen, which is fine - nobody is looking at it"
        )

        // Coming back picks up everything missed, in one read.
        viewModel.discoverDidAppear()
        await drain(viewModel)

        XCTAssertEqual(viewModel.matches.first?.missedIngredients.map(\.name), ["brown sugar"])
        XCTAssertEqual(pantry.fetchAllCount, readsOnArrival + 1, "One read on arrival, however many edits were made")
        XCTAssertEqual(service.receivedCriteria.count, 1, "No re-check may spend API quota")
    }

    /// The tab change and `DiscoverRecipesView.onAppear` both fire when the
    /// user arrives. They must not each pay for a pantry read.
    func test_tabChangeAndOnAppear_togetherCostOneRead() async throws {
        let pantry = CountingPantryRepository(seedItems: [item("egg")])
        let service = MockOnlineRecipeService(result: .success([OnlineRecipeFixtures.bakedCustard()]))
        let viewModel = makeViewModel(pantry, service)

        await viewModel.search()
        let readsAfterSearch = pantry.fetchAllCount

        // ContentView's onChange, then the view's onAppear, then the pushed
        // detail's - the real sequence when arriving and opening a recipe.
        viewModel.discoverDidAppear()
        viewModel.discoverDidAppear()
        viewModel.discoverDidAppear()
        await drain(viewModel)

        XCTAssertEqual(pantry.fetchAllCount, readsAfterSearch + 1)
        XCTAssertEqual(service.receivedCriteria.count, 1)
    }

    /// A receipt scan adds a dozen items at once. `inventoryStore.items`
    /// changes once per item, and each change used to be a full re-check.
    func test_bulkPantryUpdate_coalescesIntoOneRead() async throws {
        let pantry = CountingPantryRepository(seedItems: [item("egg")])
        let service = MockOnlineRecipeService(result: .success([OnlineRecipeFixtures.bakedCustard()]))
        let viewModel = makeViewModel(pantry, service)

        await viewModel.search()
        viewModel.discoverDidAppear()
        await drain(viewModel)
        let readsBeforeBurst = pantry.fetchAllCount

        for name in ["milk", "vanilla extract", "butter", "flour", "salt", "sugar"] {
            try await pantry.add(item(name))
            viewModel.pantryDidChange()
        }
        await drain(viewModel)

        XCTAssertEqual(pantry.fetchAllCount, readsBeforeBurst + 1, "Six edits in one burst, one pantry read")
        XCTAssertEqual(
            viewModel.matches.first?.missedIngredients.map(\.name),
            ["brown sugar"],
            "And the one read that happened used the pantry as it ended up"
        )
        XCTAssertEqual(service.receivedCriteria.count, 1)
    }

    // MARK: - What a trigger-driven re-check must preserve

    func test_hiddenRecipesStayHidden_acrossATriggeredRecheck() async throws {
        let pantry = CountingPantryRepository(seedItems: [item("egg"), item("Garlic")])
        let custard = OnlineRecipeFixtures.bakedCustard()
        let service = MockOnlineRecipeService(result: .success([custard, OnlineRecipeFixtures.match()]))
        let viewModel = makeViewModel(pantry, service)

        await viewModel.search()
        viewModel.discoverDidAppear()
        await drain(viewModel)
        viewModel.hide(custard)
        XCTAssertFalse(viewModel.matches.contains { $0.id == custard.id })

        try await pantry.add(item("milk"))
        viewModel.pantryDidChange()
        await drain(viewModel)

        XCTAssertFalse(
            viewModel.matches.contains { $0.id == custard.id },
            "A hidden recipe must not come back just because the pantry changed"
        )
        XCTAssertEqual(viewModel.excludedAsHiddenCount, 1)
        XCTAssertEqual(service.receivedCriteria.count, 1)
    }

    /// `LiveOnlineRecipeDetail` reads the match back out of `matches` by id.
    /// A pantry change while a detail screen is open therefore has to update
    /// the entry *for that id*, not just the list as a whole.
    func test_openRecipeDetail_seesTheUpdatedMatchForItsOwnID() async throws {
        let pantry = CountingPantryRepository(seedItems: [item("egg")])
        let custard = OnlineRecipeFixtures.bakedCustard()
        let service = MockOnlineRecipeService(result: .success([custard]))
        let viewModel = makeViewModel(pantry, service)

        await viewModel.search()
        viewModel.discoverDidAppear()
        await drain(viewModel)

        // The row was tapped: this is the snapshot the navigation path holds.
        let pushed = try XCTUnwrap(viewModel.matches.first { $0.id == custard.id })
        XCTAssertEqual(pushed.missedIngredients.count, 3)

        try await pantry.add(item("milk"))
        try await pantry.add(item("vanilla extract"))
        viewModel.pantryDidChange()
        await drain(viewModel)

        let live = try XCTUnwrap(viewModel.matches.first { $0.id == pushed.id })
        XCTAssertEqual(live.missedIngredients.map(\.name), ["brown sugar"])
        XCTAssertEqual(live.usedIngredientNames, ["eggs", "milk", "vanilla extract"])
        XCTAssertEqual(service.receivedCriteria.count, 1, "An open detail screen updating must not spend quota")
    }

    /// Nothing is queued before a search, so arriving on an empty Discover
    /// does not read the pantry at all.
    func test_arrivingBeforeAnySearch_readsNothing() async {
        let pantry = CountingPantryRepository(seedItems: [item("egg")])
        let service = MockOnlineRecipeService(result: .success([OnlineRecipeFixtures.bakedCustard()]))
        let viewModel = makeViewModel(pantry, service)

        viewModel.discoverDidAppear()
        viewModel.pantryDidChange()
        await drain(viewModel)

        XCTAssertEqual(pantry.fetchAllCount, 0)
        XCTAssertTrue(viewModel.matches.isEmpty)
        XCTAssertFalse(viewModel.hasSearched)
        XCTAssertTrue(service.receivedCriteria.isEmpty)
    }
}
