//
//  OnlineRecipeHidingTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class OnlineRecipeHidingTests: XCTestCase {

    // MARK: - Team blocklist file

    func test_blocklist_parsesIDs() {
        let json = #"{"recipes": [{"id": 11, "reason": "wrong photo"}, {"id": 22}]}"#
        XCTAssertEqual(OnlineRecipeBlocklist.blockedIDs(from: Data(json.utf8)), [11, 22])
        XCTAssertEqual(OnlineRecipeBlocklist.entries(from: Data(json.utf8)).first?.reason, "wrong photo")
    }

    func test_blocklist_malformedFile_isEmpty_notACrash() {
        XCTAssertEqual(OnlineRecipeBlocklist.blockedIDs(from: Data("not json".utf8)), [])
        XCTAssertEqual(OnlineRecipeBlocklist.blockedIDs(from: Data(#"{"recipes": "nope"}"#.utf8)), [])
    }

    func test_blocklist_shippedFile_isBundledAndValid() throws {
        let bundle = Bundle(for: OnlineRecipeSearchViewModel.self)
        let url = try XCTUnwrap(bundle.url(forResource: OnlineRecipeBlocklist.resourceName, withExtension: "json"),
                                "blocked_online_recipes.json must ship in the app bundle")
        let data = try Data(contentsOf: url)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }

    // MARK: - Hidden store

    func test_userDefaultsStore_roundTrips() throws {
        let suite = "hidden-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        UserDefaultsHiddenOnlineRecipeStore(defaults: defaults).save([3, 1])

        XCTAssertEqual(UserDefaultsHiddenOnlineRecipeStore(defaults: defaults).load(), [1, 3])
    }

    // MARK: - Use case

    func test_useCase_dropsExcludedIDs_andCountsThem() async throws {
        let service = MockOnlineRecipeService(result: .success([
            OnlineRecipeFixtures.match(id: 1),
            OnlineRecipeFixtures.match(id: 2),
            OnlineRecipeFixtures.match(id: 3),
        ]))
        let useCase = FindOnlineRecipesFromPantryUseCase(recipeService: service, pantryRepository: OnlineRecipeFixtures.pantry("Rice"))

        let result = try await useCase.execute(preferences: .default, excluding: [2, 99])

        XCTAssertEqual(result.matches.map(\.id).sorted(), [1, 3])
        XCTAssertEqual(result.excludedAsHiddenCount, 1)
        XCTAssertEqual(result.excludedForSafetyCount, 0)
    }

    func test_useCase_everythingExcluded_isNoResults() async {
        let useCase = FindOnlineRecipesFromPantryUseCase(
            recipeService: MockOnlineRecipeService(result: .success([OnlineRecipeFixtures.match(id: 5)])),
            pantryRepository: OnlineRecipeFixtures.pantry("Rice")
        )
        do {
            _ = try await useCase.execute(preferences: .default, excluding: [5])
            XCTFail("Expected noResults")
        } catch {
            XCTAssertEqual(error as? OnlineRecipeSearchError, .noResults)
        }
    }

    // MARK: - View model

    private func makeViewModel(
        store: InMemoryHiddenOnlineRecipeStore = InMemoryHiddenOnlineRecipeStore(),
        blocked: Set<Int> = []
    ) -> (OnlineRecipeSearchViewModel, MockOnlineRecipeService) {
        let service = MockOnlineRecipeService(result: .success([
            OnlineRecipeFixtures.match(id: 1),
            OnlineRecipeFixtures.match(id: 2),
            OnlineRecipeFixtures.match(id: 3),
        ]))
        let viewModel = OnlineRecipeSearchViewModel(
            useCase: FindOnlineRecipesFromPantryUseCase(recipeService: service, pantryRepository: OnlineRecipeFixtures.pantry("Rice")),
            preferencesStore: InMemoryOnlineRecipePreferencesStore(),
            hiddenRecipeStore: store,
            blockedRecipeIDs: blocked
        )
        return (viewModel, service)
    }

    func test_hide_removesNow_persists_andStaysHiddenNextSearch() async {
        let store = InMemoryHiddenOnlineRecipeStore()
        let (viewModel, _) = makeViewModel(store: store)
        await viewModel.search()
        let target = viewModel.matches.first { $0.id == 2 }!

        viewModel.hide(target)

        XCTAssertFalse(viewModel.matches.contains { $0.id == 2 })
        XCTAssertEqual(store.ids, [2])

        await viewModel.search()
        XCTAssertFalse(viewModel.matches.contains { $0.id == 2 })
        XCTAssertEqual(viewModel.excludedAsHiddenCount, 1)
    }

    func test_teamBlocklist_isAlwaysExcluded_evenAfterUnhideAll() async {
        let (viewModel, _) = makeViewModel(store: InMemoryHiddenOnlineRecipeStore(ids: [1]), blocked: [3])

        await viewModel.search()
        XCTAssertEqual(viewModel.matches.map(\.id), [2])

        viewModel.unhideAll()
        await viewModel.search()

        XCTAssertEqual(viewModel.matches.map(\.id).sorted(), [1, 2], "Unhide restores user-hidden recipes, never blocklisted ones")
        XCTAssertTrue(viewModel.hiddenRecipeIDs.isEmpty)
    }
}
