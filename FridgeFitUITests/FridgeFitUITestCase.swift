//
//  FridgeFitUITestCase.swift
//  FridgeFitUITests
//

import XCTest

// Shared setup + helpers so the actual test files stay short.
// The app is launched with -uiTesting, which skips login and swaps
// Firestore / Apple Intelligence / OpenRouter for in-memory fakes
// (see AppDependencies.swift in the app target).
@MainActor
class FridgeFitUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
    }

    // Pass something like "Eggs:6:pcs,Milk:500:ml" to start with a filled pantry.
    func launch(pantry: String? = nil) {
        if let pantry {
            app.launchEnvironment["UITEST_PANTRY"] = pantry
        }
        app.launch()
    }

    func addIngredient(name: String, quantity: String) {
        app.buttons["pantry.addButton"].tap()

        let nameField = app.textFields["addItem.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Add sheet never showed up")
        nameField.tap()
        nameField.typeText(name)

        let quantityField = app.textFields["addItem.quantity"]
        quantityField.tap()
        quantityField.typeText(quantity)

        app.buttons["addItem.save"].tap()
    }

    func pantryRow(_ name: String) -> XCUIElement {
        app.buttons["pantry.row.\(name)"]
    }

    func openRecipesTab() {
        app.tabBars.buttons["Recipes"].tap()
        XCTAssertTrue(app.navigationBars["Recipes"].waitForExistence(timeout: 5))
    }

    // Recipe list is lazy, so rows further down don't exist until you scroll to them.
    func recipeRow(_ title: String) -> XCUIElement {
        let row = app.buttons["recipe.row.\(title)"]
        var swipes = 0
        while !row.exists && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        return row
    }

    // Waits until the element's accessibility label contains some text.
    // Handy for the recipe rows, the feasibility bit loads a moment after the title.
    func waitForLabel(of element: XCUIElement, toContain text: String, timeout: TimeInterval = 5) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Label was '\(element.label)', expected it to contain '\(text)'")
    }

    // Text fields here come prefilled, so wipe whatever's in there first.
    func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        field.typeText(text)
    }
}
