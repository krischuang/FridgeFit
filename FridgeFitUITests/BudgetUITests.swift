//
//  BudgetUITests.swift
//  FridgeFitUITests
//

import XCTest

// FridgeFunds in the Budget tab. in -uiTesting mode its data is in-memory, but it
// still reads the same (seeded) pantry as the rest of the app.
final class BudgetUITests: FridgeFitUITestCase {

    // first launch after install can be slow (Firebase setup etc), so give the tab
    // bar a moment before tapping instead of assuming it's there
    private func openBudgetTab() {
        let tab = app.tabBars.buttons["Budget"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()
    }

    private func setBudget(_ amount: String) {
        let field = app.textFields["e.g. 120"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Budget setup card never showed up")
        field.tap()
        field.typeText(amount)
        app.buttons["Start tracking"].tap()
    }

    func test_firstVisit_asksForABudget() {
        launch()
        openBudgetTab()

        XCTAssertTrue(app.textFields["e.g. 120"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Set your food budget"].exists)
        XCTAssertTrue(app.buttons["Start tracking"].exists)
    }

    func test_settingABudget_showsTheDashboard() {
        launch()
        openBudgetTab()

        setBudget("120")

        XCTAssertTrue(app.staticTexts["Left to spend today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["$0.00 spent of $120.00"].exists)
    }

    func test_loggingASpend_showsUpInHistory() {
        launch()
        openBudgetTab()
        setBudget("120")

        app.buttons["Log a spend"].tap()
        let amount = app.textFields["Amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("35")
        app.buttons["Log Spend"].tap()
        // $35 on day one of a $120 week means "at this pace you'll go over", so the
        // app shows the gentle warning instead of the plain confirmation - both end
        // in "logged" and the spend is saved either way
        let saved = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'logged'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Spend & waste history"].tap()
        XCTAssertTrue(app.staticTexts["$35.00"].waitForExistence(timeout: 5))
    }

    // the actual point of the integration: what's in the FridgeFit pantry shows up
    // here, and once you give it a price it counts towards "money in your fridge"
    func test_pantryItems_showUp_andCanBePriced() {
        launch(pantry: "Eggs:6:pcs")
        openBudgetTab()
        setBudget("120")

        app.buttons["Money in my fridge"].tap()
        // the identifier gets copied onto the texts inside the row too, so just take the first
        let eggs = app.descendants(matching: .any)["funds.item.Eggs"].firstMatch
        XCTAssertTrue(eggs.waitForExistence(timeout: 5), "Pantry item never reached FridgeFunds")
        XCTAssertTrue(app.staticTexts["No price"].exists)

        eggs.tap()
        let total = app.textFields["funds.price.total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        total.tap()
        total.typeText("3")
        app.buttons["funds.price.save"].tap()

        // shows on the row and in the "Total value" summary
        XCTAssertTrue(app.staticTexts["$3.00"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No price"].exists)
    }
    // price typed straight into the Pantry tab's add form
    func test_priceFromTheAddForm_showsUpInTheBudgetTab() {
        launch()
        openBudgetTab()
        setBudget("120")

        app.tabBars.buttons["Pantry"].tap()
        app.buttons["pantry.addButton"].tap()
        let name = app.textFields["addItem.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Milk")
        let quantity = app.textFields["addItem.quantity"]
        quantity.tap()
        quantity.typeText("2")
        let price = app.textFields["addItem.price"]
        price.tap()
        price.typeText("4.50")
        app.buttons["addItem.save"].tap()
        XCTAssertTrue(app.buttons["pantry.row.Milk"].waitForExistence(timeout: 5))

        openBudgetTab()
        app.buttons["Money in my fridge"].tap()
        XCTAssertTrue(app.staticTexts["$4.50"].waitForExistence(timeout: 5))
    }
}
