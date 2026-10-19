//
//  RecipeCostUITests.swift
//  FridgeFitUITests
//

import XCTest

// prices recorded in the Budget tab show up as a cost estimate on the recipe
// detail screen. "Classic Cheese Omelette" needs 3 eggs, 30 ml milk, 50 g cheddar.
final class RecipeCostUITests: FridgeFitUITestCase {

    private func price(_ item: String, total: String) {
        let row = app.descendants(matching: .any)["funds.item.\(item)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "\(item) never showed up in Money in my fridge")
        row.tap()
        let field = app.textFields["funds.price.total"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(total)
        app.buttons["funds.price.save"].tap()
    }

    // the cost section is below the ingredients, so scroll till it's there
    private func scrollTo(_ identifier: String) -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        var swipes = 0
        while !element.exists && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        return element
    }

    func test_recipeDetail_showsCost_fromRecordedPrices() {
        launch(pantry: "Eggs:6:pcs,Milk:500:ml")

        // a budget so there's something to compare against
        selectTab("Budget")
        let budgetField = app.textFields["e.g. 120"]
        XCTAssertTrue(budgetField.waitForExistence(timeout: 10))
        budgetField.tap()
        budgetField.typeText("120")
        app.buttons["Start tracking"].tap()

        // $3 for 6 eggs, $2 for 500 ml milk
        app.buttons["Money in my fridge"].tap()
        price("Eggs", total: "3")
        price("Milk", total: "2")

        openRecipesTab()
        let omelette = recipeRow("Classic Cheese Omelette")
        XCTAssertTrue(omelette.waitForExistence(timeout: 5))
        omelette.tap()

        // 3 x $0.50 + 30 ml x $0.004 = $1.62 from the pantry; no cheddar price anywhere
        let fromPantry = scrollTo("recipe.cost.fromPantry")
        XCTAssertTrue(fromPantry.waitForExistence(timeout: 5), "Cost section never showed up")
        waitForLabel(of: fromPantry, toContain: "$1.62")

        let unpriced = scrollTo("recipe.cost.unpriced")
        XCTAssertTrue(unpriced.exists)
        XCTAssertTrue(unpriced.label.contains("Cheddar"), "Label was '\(unpriced.label)'")

        // nothing priced to buy, budget's untouched
        XCTAssertTrue(scrollTo("recipe.cost.budget").exists)
    }

    func test_recipeDetail_withoutAnyPrices_saysSo() {
        launch()
        openRecipesTab()
        let omelette = recipeRow("Classic Cheese Omelette")
        XCTAssertTrue(omelette.waitForExistence(timeout: 5))
        omelette.tap()

        let unpriced = scrollTo("recipe.cost.unpriced")
        XCTAssertTrue(unpriced.waitForExistence(timeout: 5))
        XCTAssertTrue(unpriced.label.contains("Eggs"))
        // no budget set yet
        let budget = scrollTo("recipe.cost.budget")
        XCTAssertTrue(budget.label.contains("Set a budget"), "Label was '\(budget.label)'")
    }
}
