//
//  OnlineRecipePantryReconcilerTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class OnlineRecipePantryReconcilerTests: XCTestCase {

    private func line(_ name: String, id: Int) -> OnlineRecipeIngredient {
        OnlineRecipeIngredient(providerID: id, name: name, amount: 1, unit: .pieces, originalUnit: "")
    }

    private func pantry(_ names: String...) -> [PantryItem] {
        names.map { PantryItem(ingredient: Ingredient(name: $0), quantity: 1, unit: .pieces) }
    }

    /// Spoonacular's shape for the reported case: brown sugar is in the
    /// ingredient list but in neither used nor missed, because the provider
    /// assumes pantry staples are owned.
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

    // MARK: - The reported bug

    func test_bakedCustard_withEggAndBeef_hasOneMatchedAndThreeMissing() {
        let result = OnlineRecipePantryReconciler.reconciled(bakedCustard(), pantry: pantry("egg", "beef"))

        XCTAssertEqual(result.usedIngredientNames, ["eggs"])
        XCTAssertEqual(result.missedIngredients.map(\.name), ["brown sugar", "milk", "vanilla extract"])
        XCTAssertTrue(result.isMissing(line("brown sugar", id: 19334)), "An assumed staple is missing unless the pantry has it")
    }

    func test_assumedStaple_countsOnlyWhenThePantryHasIt() {
        let result = OnlineRecipePantryReconciler.reconciled(bakedCustard(), pantry: pantry("egg", "Brown Sugar"))

        XCTAssertEqual(result.usedIngredientNames, ["eggs", "brown sugar"])
        XCTAssertEqual(result.missedIngredients.map(\.name), ["milk", "vanilla extract"])
    }

    // MARK: - Evidence for "have"

    func test_pantryMatch_countsEvenIfTheProviderDidNotReportIt() {
        var match = bakedCustard()
        match.usedIngredientNames = []

        let result = OnlineRecipePantryReconciler.reconciled(match, pantry: pantry("Eggs"))

        XCTAssertEqual(result.usedIngredientNames, ["eggs"])
    }

    /// The provider matched "ground beef" to the pantry name "beef" we sent;
    /// that's evidence from the user's pantry, so it is kept.
    func test_providerReportedUse_isKept_forLooserMatchesItMade() {
        var recipe = OnlineRecipeFixtures.recipe(id: 1)
        recipe.ingredients = [line("ground beef", id: 10220), line("onion", id: 11282)]
        let match = OnlineRecipeMatch(recipe: recipe, usedIngredientNames: ["ground beef"], missedIngredients: [line("onion", id: 11282)])

        let result = OnlineRecipePantryReconciler.reconciled(match, pantry: pantry("beef"))

        XCTAssertEqual(result.usedIngredientNames, ["ground beef"])
        XCTAssertEqual(result.missedIngredients.map(\.name), ["onion"])
    }

    func test_noIngredientList_isLeftAsTheProviderSentIt() {
        var match = bakedCustard()
        match.recipe.ingredients = []

        let result = OnlineRecipePantryReconciler.reconciled(match, pantry: pantry("egg"))

        XCTAssertEqual(result, match)
    }

    // MARK: - Through the use case

    func test_useCase_countsAndRanksByThePantry_notByTheProvidersAssumptions() async throws {
        // Provider says "Custard" misses 2 and "Omelette" misses 1, but
        // Omelette's "missing" salt is in the pantry while Custard's sugar
        // is assumed - so after reconciling Omelette misses 0, Custard 3.
        var omelette = OnlineRecipeFixtures.recipe(id: 2, title: "Omelette")
        omelette.ingredients = [line("eggs", id: 1123), line("salt", id: 2047)]
        let omeletteMatch = OnlineRecipeMatch(recipe: omelette, usedIngredientNames: ["eggs"], missedIngredients: [line("salt", id: 2047)])

        let useCase = FindOnlineRecipesFromPantryUseCase(
            recipeService: MockOnlineRecipeService(result: .success([bakedCustard(), omeletteMatch])),
            pantryRepository: OnlineRecipeFixtures.pantry("egg", "beef", "salt")
        )

        let result = try await useCase.execute(preferences: .default)

        XCTAssertEqual(result.matches.map(\.recipe.title), ["Omelette", "Baked Custard"])
        let custard = try XCTUnwrap(result.matches.first { $0.recipe.title == "Baked Custard" })
        XCTAssertEqual(custard.usedIngredientNames.count, 1)
        XCTAssertEqual(custard.missedIngredients.count, 3)
        let omeletteResult = try XCTUnwrap(result.matches.first { $0.recipe.title == "Omelette" })
        XCTAssertTrue(omeletteResult.missedIngredients.isEmpty)
    }
}
