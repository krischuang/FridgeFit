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
        OnlineRecipeFixtures.line(name, id: id)
    }

    private func item(_ name: String) -> PantryItem {
        PantryItem(ingredient: Ingredient(name: name, category: .other), quantity: 1, unit: .pieces)
    }

    private func bakedCustard() -> OnlineRecipeMatch {
        OnlineRecipeFixtures.bakedCustard()
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

    // MARK: - Filter changes

    /// `diet`, `cuisine` and `maxReadyTime` are applied by the provider, so
    /// results fetched under the old filters can never be re-checked into
    /// compliance locally. Clearing them has to include the cached provider
    /// response, or the next pantry change puts them straight back.
    func test_updatePreferences_clearsCachedProviderResults_soNoRefreshRestoresThem() async {
        let pantry = OnlineRecipeFixtures.pantry("egg")
        let service = MockOnlineRecipeService(result: .success([bakedCustard()]))
        let viewModel = OnlineRecipeSearchViewModel(
            useCase: FindOnlineRecipesFromPantryUseCase(recipeService: service, pantryRepository: pantry),
            preferencesStore: InMemoryOnlineRecipePreferencesStore()
        )
        await viewModel.search()
        XCTAssertFalse(viewModel.matches.isEmpty)

        viewModel.updatePreferences(OnlineRecipePreferences(diet: .vegetarian))
        await viewModel.refreshPantryMatch()

        XCTAssertTrue(viewModel.matches.isEmpty, "Results fetched under the previous filters must not come back")
        XCTAssertFalse(viewModel.hasSearched, "hasSearched and the visible results must stay consistent")
        XCTAssertEqual(service.receivedCriteria.count, 1, "Clearing filters must not spend quota by itself")
    }

    // MARK: - Descriptor words

    func test_namesMatch_ignoresLeadingDescriptors() {
        XCTAssertTrue(OnlineRecipeExpiryRanking.namesMatch("mild cheddar cheese", "Cheddar Cheese"))
        XCTAssertTrue(OnlineRecipeExpiryRanking.namesMatch("large eggs", "egg"))
        XCTAssertTrue(OnlineRecipeExpiryRanking.namesMatch("cheddar cheese", "Mild Cheddar Cheese"))
        XCTAssertTrue(OnlineRecipeExpiryRanking.namesMatch("freshly grated parmesan", "parmesan"))
    }

    func test_namesMatch_keepsWordsThatChangeTheIngredient() {
        XCTAssertFalse(OnlineRecipeExpiryRanking.namesMatch("brown sugar", "sugar"))
        XCTAssertFalse(OnlineRecipeExpiryRanking.namesMatch("sweet potato", "potato"))
        XCTAssertFalse(OnlineRecipeExpiryRanking.namesMatch("cheddar cheese", "cheese"))
    }

    func test_reconcile_mildCheddar_isMatchedByPantryCheddar() {
        var recipe = OnlineRecipeFixtures.recipe(id: 7, title: "Mac and Cheese")
        recipe.ingredients = [line("mild cheddar cheese", id: 1009), line("macaroni", id: 20099)]
        let match = OnlineRecipeMatch(recipe: recipe, usedIngredientNames: [], missedIngredients: recipe.ingredients)

        let result = OnlineRecipePantryReconciler.reconciled(match, pantry: [item("Cheddar Cheese")])

        XCTAssertEqual(result.usedIngredientNames, ["mild cheddar cheese"])
        XCTAssertEqual(result.missedIngredients.map(\.name), ["macaroni"])
    }

    // MARK: - Deducting from My Fridge

    func test_reconcile_itemUsedUpToZero_isMissing() {
        var egg = item("egg")
        egg.quantity = 0

        let result = OnlineRecipePantryReconciler.reconciled(bakedCustard(), pantry: [egg])

        XCTAssertTrue(result.usedIngredientNames.isEmpty, "An item used up to zero is not 'have', even though the provider reported eggs as used")
        XCTAssertEqual(result.missedIngredients.count, 4)
    }

    func test_reconcile_providerReportedUsed_isDroppedOnceThePantryItemIsGone() {
        var recipe = OnlineRecipeFixtures.recipe(id: 9, title: "Chilli")
        recipe.ingredients = [line("ground beef", id: 10220), line("onion", id: 11282)]
        let match = OnlineRecipeMatch(recipe: recipe, usedIngredientNames: ["ground beef"], missedIngredients: [line("onion", id: 11282)])

        let withBeef = OnlineRecipePantryReconciler.reconciled(match, pantry: [item("beef")])
        let withoutBeef = OnlineRecipePantryReconciler.reconciled(match, pantry: [item("onion")])

        XCTAssertEqual(withBeef.usedIngredientNames, ["ground beef"])
        XCTAssertEqual(withoutBeef.usedIngredientNames, ["onion"])
        XCTAssertEqual(withoutBeef.missedIngredients.map(\.name), ["ground beef"])
    }

    func test_refreshPantryMatch_afterDeductingToZero_marksItMissing() async throws {
        let pantry = OnlineRecipeFixtures.pantry("egg", "milk")
        let service = MockOnlineRecipeService(result: .success([bakedCustard()]))
        let viewModel = OnlineRecipeSearchViewModel(
            useCase: FindOnlineRecipesFromPantryUseCase(recipeService: service, pantryRepository: pantry),
            preferencesStore: InMemoryOnlineRecipePreferencesStore()
        )
        await viewModel.search()

        let all = try await pantry.fetchAll()
        var milk = try XCTUnwrap(all.first { $0.name == "milk" })
        milk.quantity = 0
        try await pantry.update(milk)
        await viewModel.refreshPantryMatch()

        let missing = viewModel.matches.first?.missedIngredients.map(\.name)
        XCTAssertEqual(missing, ["brown sugar", "milk", "vanilla extract"])
        XCTAssertEqual(service.receivedCriteria.count, 1)
    }
}
