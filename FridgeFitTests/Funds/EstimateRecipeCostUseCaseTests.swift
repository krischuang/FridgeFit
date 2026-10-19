//
//  EstimateRecipeCostUseCaseTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

// recipe cost from recorded prices: pantry price first, price book for anything
// missing, nothing made up when there's no price at all
@MainActor
final class EstimateRecipeCostUseCaseTests: XCTestCase {

    private func ingredient(_ name: String, _ quantity: Double, _ unit: MeasurementUnit,
                            _ role: IngredientRole = .essential) -> RecipeIngredient {
        RecipeIngredient(ingredient: Ingredient(name: name), quantity: quantity, unit: unit, role: role)
    }

    private func recipe(_ ingredients: [RecipeIngredient], servings: Int? = nil) -> Recipe {
        Recipe(title: "Test", summary: "", servings: servings, ingredients: ingredients, instructions: [])
    }

    private func snapshot(_ name: String, _ quantity: Double, _ unit: MeasurementUnit, cost: Decimal?) -> PantryItemSnapshot {
        PantryItemSnapshot(id: PantryItemID(name), name: name, quantity: quantity, unit: unit.rawValue,
                           unitCost: cost.map { aud($0) })
    }

    private func estimate(_ recipe: Recipe,
                          pantry: [PantryItemSnapshot] = [],
                          book: [PriceBookEntry] = [],
                          budget: FoodBudget? = makeWeeklyBudget(limit: 100),
                          spends: [GrocerySpend] = []) -> RecipeCostEstimate {
        let useCase = EstimateRecipeCostUseCase(
            pantry: InMemoryPantryReading(items: pantry),
            priceBook: InMemoryPriceBookStore(book),
            budgetStore: InMemoryBudgetStore(budget: budget, spends: spends)
        )
        return useCase.execute(recipe: recipe, now: TestDates.day(1))
    }

    private func dec(_ s: String) -> Decimal { Decimal(string: s)! }

    func test_everythingInThePantry_costsWhatYouUse_nothingToBuy() async {
        let result = estimate(
            recipe([ingredient("Eggs", 3, .pieces), ingredient("Milk", 30, .milliliters)]),
            pantry: [snapshot("Eggs", 12, .pieces, cost: dec("0.5")), snapshot("Milk", 1000, .milliliters, cost: dec("0.004"))]
        )

        // 3 x 0.50 + 30 x 0.004
        XCTAssertEqual(result.fromPantry, aud(dec("1.62")))
        XCTAssertEqual(result.toBuy, aud(0))
        XCTAssertTrue(result.isComplete)
    }

    func test_notEnoughInThePantry_shortfallIsCostedAtTheSamePrice() async {
        let result = estimate(
            recipe([ingredient("Eggs", 3, .pieces)]),
            pantry: [snapshot("Eggs", 1, .pieces, cost: dec("0.5"))]
        )

        XCTAssertEqual(result.fromPantry, aud(dec("0.5")))
        XCTAssertEqual(result.toBuy, aud(1))
    }

    func test_unitsAreConverted_kgPriceForAGramRecipe() async {
        // $12/kg chicken, recipe wants 400 g
        let result = estimate(
            recipe([ingredient("Chicken Breast", 400, .grams)]),
            pantry: [snapshot("Chicken Breast", 1, .kilograms, cost: 12)]
        )

        XCTAssertEqual(result.fromPantry, aud(dec("4.8")))
    }

    func test_missingIngredient_usesThePriceBook() async {
        // bought cheddar before at $12/kg, none left now
        let result = estimate(
            recipe([ingredient("Cheddar", 50, .grams)]),
            book: [PriceBookEntry(displayName: "Cheddar", unitCost: aud(12), unit: "kg")]
        )

        XCTAssertEqual(result.toBuy, aud(dec("0.6")))
        XCTAssertTrue(result.isComplete)
    }

    func test_priceBookMatch_ignoresCaseAndSpaces() async {
        let result = estimate(
            recipe([ingredient("  cheddar ", 100, .grams)]),
            book: [PriceBookEntry(displayName: "Cheddar", unitCost: aud(dec("0.01")), unit: "g")]
        )

        XCTAssertEqual(result.toBuy, aud(1))
    }

    func test_inPantryButUnpriced_fallsBackToThePriceBook() async {
        let result = estimate(
            recipe([ingredient("Rice", 300, .grams)]),
            pantry: [snapshot("Rice", 1000, .grams, cost: nil)],
            book: [PriceBookEntry(displayName: "Rice", unitCost: aud(3), unit: "kg")]
        )

        XCTAssertEqual(result.fromPantry, aud(dec("0.9")))
        XCTAssertTrue(result.isComplete)
    }

    func test_noPriceAnywhere_isListed_notGuessed() async {
        let result = estimate(recipe([ingredient("Saffron", 1, .grams), ingredient("Eggs", 2, .pieces)]),
                              pantry: [snapshot("Eggs", 6, .pieces, cost: dec("0.5"))])

        XCTAssertEqual(result.unpricedNames, ["Saffron"])
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.fromPantry, aud(1))
        XCTAssertEqual(result.toBuy, aud(0))
        XCTAssertEqual(result.lines.first?.unpricedReason, "No price yet")
    }

    func test_unitsThatDontConvert_areLeftUnpriced() async {
        // cups vs ml isn't a safe conversion in this app
        let result = estimate(recipe([ingredient("Milk", 1, .cups)]),
                              pantry: [snapshot("Milk", 1000, .milliliters, cost: dec("0.004"))])

        XCTAssertEqual(result.unpricedNames, ["Milk"])
        XCTAssertEqual(result.lines.first?.unpricedReason, "Can't compare units")
    }

    func test_optionalIngredients_areShown_butNotCounted() async {
        let result = estimate(
            recipe([ingredient("Eggs", 2, .pieces), ingredient("Parsley", 10, .grams, .optional)]),
            pantry: [snapshot("Eggs", 6, .pieces, cost: dec("0.5"))],
            book: [PriceBookEntry(displayName: "Parsley", unitCost: aud(dec("0.2")), unit: "g")]
        )

        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.lines.last?.toBuy, aud(2))
        XCTAssertEqual(result.total, aud(1))
    }

    func test_perServing() async {
        let result = estimate(recipe([ingredient("Eggs", 4, .pieces)], servings: 2),
                              pantry: [snapshot("Eggs", 12, .pieces, cost: dec("0.75"))])

        XCTAssertEqual(result.perServing, aud(dec("1.5")))
    }

    func test_perServing_isNil_whenRecipeDoesntSay() async {
        let result = estimate(recipe([ingredient("Eggs", 4, .pieces)]),
                              pantry: [snapshot("Eggs", 12, .pieces, cost: 1)])

        XCTAssertNil(result.perServing)
    }

    func test_budget_fits_whenShoppingIsUnderWhatsLeft() async {
        // $100 week, $30 already spent, need to buy $0.60 of cheddar
        let result = estimate(
            recipe([ingredient("Cheddar", 50, .grams)]),
            book: [PriceBookEntry(displayName: "Cheddar", unitCost: aud(12), unit: "kg")],
            spends: [GrocerySpend(amount: aud(30), spentOn: TestDates.day(0))]
        )

        XCTAssertEqual(result.remainingBudget, aud(70))
        XCTAssertEqual(result.fitsRemainingBudget, true)
    }

    func test_budget_doesntFit_whenShoppingIsOverWhatsLeft() async {
        let result = estimate(
            recipe([ingredient("Steak", 1, .kilograms)]),
            book: [PriceBookEntry(displayName: "Steak", unitCost: aud(40), unit: "kg")],
            budget: makeWeeklyBudget(limit: 50),
            spends: [GrocerySpend(amount: aud(30), spentOn: TestDates.day(0))]
        )

        XCTAssertEqual(result.fitsRemainingBudget, false)
    }

    func test_noBudget_meansNothingToCompare() async {
        let result = estimate(recipe([ingredient("Eggs", 1, .pieces)]),
                              pantry: [snapshot("Eggs", 6, .pieces, cost: 1)],
                              budget: nil)

        XCTAssertNil(result.remainingBudget)
        XCTAssertNil(result.fitsRemainingBudget)
    }

    func test_pricesInAnotherCurrency_arentMixedIn() async {
        // budget is AUD, the only price we have is USD
        let result = estimate(
            recipe([ingredient("Cheddar", 50, .grams)]),
            book: [PriceBookEntry(displayName: "Cheddar", unitCost: Money(10, .usd), unit: "kg")]
        )

        XCTAssertEqual(result.unpricedNames, ["Cheddar"])
    }
}
