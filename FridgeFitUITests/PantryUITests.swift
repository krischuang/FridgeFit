//
//  PantryUITests.swift
//  FridgeFitUITests
//

import XCTest

final class PantryUITests: FridgeFitUITestCase {

    func test_emptyPantry_showsEmptyState() {
        launch()

        XCTAssertTrue(app.staticTexts["Your Pantry Is Empty"].waitForExistence(timeout: 5))
    }

    func test_addIngredient_showsUpInTheList() {
        launch()

        addIngredient(name: "Eggs", quantity: "6")

        let row = pantryRow("Eggs")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        // unit picker defaults to grams, we didn't touch it
        waitForLabel(of: row, toContain: "6 g")
    }

    func test_addIngredient_withNoName_staysOnTheSheetWithAnError() {
        launch()

        addIngredient(name: "", quantity: "2")

        let error = app.staticTexts["Please enter an ingredient name so FridgeFit knows what to add."]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        // sheet should still be open, nothing got added
        XCTAssertTrue(app.buttons["addItem.save"].exists)
    }

    func test_addingTheSameIngredientTwice_offersToUpdateTheExistingOne() {
        launch(pantry: "Eggs:6:pcs")

        // lowercase on purpose, the duplicate check ignores case
        addIngredient(name: "eggs", quantity: "2")

        XCTAssertTrue(app.buttons["Update Existing Quantity"].waitForExistence(timeout: 5))
    }

    func test_updateQuantity_changesWhatTheRowShows() {
        launch(pantry: "Milk:500:ml")

        let row = pantryRow("Milk")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let quantityField = app.textFields["updateItem.quantity"]
        XCTAssertTrue(quantityField.waitForExistence(timeout: 5))
        replaceText(in: quantityField, with: "250")
        app.buttons["updateItem.save"].tap()

        waitForLabel(of: pantryRow("Milk"), toContain: "250 ml")
    }

    func test_swipeToDelete_removesTheIngredient() {
        launch(pantry: "Butter:20:g")

        let row = pantryRow("Butter")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Delete"].tap()

        XCTAssertTrue(app.staticTexts["Your Pantry Is Empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(row.exists)
    }
}
