//
//  DiscoverPantryRefreshTests.swift
//  FridgeFitTests
//
//  After a search, changing the pantry must update Discover's
//  matched / missing ingredients without another API call.
//

import XCTest
@testable import FridgeFit

@MainActor
final class DiscoverPantryRefreshTests: XCTestCase {

    private func line(_ name: String, id: Int) -> OnlineRecipeIngredient {
        OnlineRecipeIngredient(providerID: id, name: name, amount: 1, unit: .pieces, originalUnit: "")
    }

    private func item(_ name: String) -> PantryItem {
        PantryItem(ingredient: Ingredient(name: name, category: .other), quantity: 1, unit: .pieces)
    }

    private func bakedCustard() -> OnlineRecipeMatch {
        var recipe = OnlineRecipeFixtures.recipe(id: 641_000, title: "Baked Custard")
        recipe.ingredients = [
            line("eggs", id: 1123),
            line("brown sugar", id: 19334),
            line("milk", id: 1077),
            line("vanilla extract", id: 2050),
        ]
        return OnlineRecipeMatch(
            recipe: recipe,
            usedIngredientNames: ["eggs"],
            missedIngredients: [line("milk", id: 1077), line("vanilla extract", id: 2050)]
        )
    }

    // MARK: - Use case

    func test_reevaluate_usesNewPantry_withoutCallingTheProvider() async throws {
        let pantry = OnlineRecipeFixtures.pantry("egg")
        let service = MockOnlineRecipeService(result: .success([bakedCustard()]))
        let useCase = FindOnlineRecipesFromPantryUseCase(recipeService: service, pantryRepository: pantry)

        let first = try await useCase.execute(preferences: .default)
        let before = first.matches.first?.missedIngredients.count
        XCTAssertEqual(before, 3)

        try await pantry.add(item("Milk"))
        let second = try await useCase.reevaluate(providerMatches: first.providerMatches, preferences: .default)

        let custard = try XCTUnwrap(second.matches.first)
        XCTAssertEqual(custard.missedIngredients.map(\.name), ["brown sugar", "vanilla extract"])
        XCTAssertEqual(custard.usedIngredientNames, ["eggs", "milk"])
        XCTAssertEqual(service.receivedCriteria.count, 1, "Re-checking the pantry must not spend API quota")
    }

    func test_reevaluate_removedPantryItem_becomesMissingAgain() async throws {
        let pantry = OnlineRecipeFixtures.pantry("egg", "milk")
        let useCase = FindOnlineRecipesFromPantryUseCase(
            recipeService: MockOnlineRecipeService(result: .success([bakedCustard()])),
            pantryRepository: pantry
        )
        let first = try await useCase.execute(preferences: .default)
        let all = try await pantry.fetchAll()
        let milk = try XCTUnwrap(all.first { $0.name == "milk" })

        try await pantry.remove(id: milk.id)
        let second = try await useCase.reevaluate(providerMatches: first.providerMatches, preferences: .default)

        let missing = second.matches.first?.missedIngredients.map(\.name)
        XCTAssertEqual(missing, ["brown sugar", "milk", "vanilla extract"])
    }

    func test_reevaluate_keepsHiddenRecipesOut() async throws {
        let useCase = FindOnlineRecipesFromPantryUseCase(
            recipeService: MockOnlineRecipeService(result: .success([bakedCustard(), OnlineRecipeFixtures.match()])),
            pantryRepository: OnlineRecipeFixtures.pantry("egg", "Garlic")
        )
        let first = try await useCase.execute(preferences: .default)

        let second = try await useCase.reevaluate(
            providerMatches: first.providerMatches,
            preferences: .default,
            excluding: [641_000]
        )

        XCTAssertEqual(second.matches.map(\.id), [1])
        XCTAssertEqual(second.excludedAsHiddenCount, 1)
    }

    // MARK: - View model

    func test_refreshPantryMatch_updatesMissing_withoutAnotherSearch() async throws {
        let pantry = OnlineRecipeFixtures.pantry("egg")
        let service = MockOnlineRecipeService(result: .success([bakedCustard()]))
        let viewModel = OnlineRecipeSearchViewModel(
            useCase: FindOnlineRecipesFromPantryUseCase(recipeService: service, pantryRepository: pantry),
            preferencesStore: InMemoryOnlineRecipePreferencesStore()
        )
        await viewModel.search()

        try await pantry.add(item("vanilla extract"))
        await viewModel.refreshPantryMatch()

        let missing = viewModel.matches.first?.missedIngredients.map(\.name)
        XCTAssertEqual(missing, ["brown sugar", "milk"])
        XCTAssertEqual(service.receivedCriteria.count, 1)
    }

    func test_refreshPantryMatch_beforeAnySearch_doesNothing() async {
        let service = MockOnlineRecipeService(result: .success([bakedCustard()]))
        let viewModel = OnlineRecipeSearchViewModel(
            useCase: FindOnlineRecipesFromPantryUseCase(
                recipeService: service,
                pantryRepository: OnlineRecipeFixtures.pantry("egg")
            ),
            preferencesStore: InMemoryOnlineRecipePreferencesStore()
        )

        await viewModel.refreshPantryMatch()

        XCTAssertTrue(viewModel.matches.isEmpty)
        XCTAssertFalse(viewModel.hasSearched)
        XCTAssertTrue(service.receivedCriteria.isEmpty)
    }
}
