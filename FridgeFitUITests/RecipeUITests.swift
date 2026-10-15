//
//  RecipeUITests.swift
//  FridgeFitUITests
//

import XCTest

// Recipes come from the bundled list. The one used most here is
// "Classic Cheese Omelette": 3 eggs, 30 ml milk, 50 g cheddar (+ optional butter).
final class RecipeUITests: FridgeFitUITestCase {

    func test_recipe_isMakeable_whenPantryHasEverything() {
        launch(pantry: "Eggs:6:pcs,Milk:500:ml,Cheddar:200:g")
        openRecipesTab()

        let omelette = recipeRow("Classic Cheese Omelette")
        XCTAssertTrue(omelette.waitForExistence(timeout: 5))
        waitForLabel(of: omelette, toContain: "Makeable")
    }

    func test_recipe_isAlmostMakeable_whenOneThingIsMissing() {
        launch(pantry: "Eggs:6:pcs,Milk:500:ml")
        openRecipesTab()

        // 2 out of 3 essentials, so it's "almost"
        waitForLabel(of: recipeRow("Classic Cheese Omelette"), toContain: "Almost makeable")
    }

    func test_recipe_isNotMakeable_withAnEmptyPantry() {
        launch()
        openRecipesTab()

        waitForLabel(of: recipeRow("Classic Cheese Omelette"), toContain: "Not makeable")
    }

    func test_recipeStatus_updates_afterAddingTheMissingIngredient() {
        launch(pantry: "Eggs:6:pcs,Milk:500:ml")
        openRecipesTab()
        waitForLabel(of: recipeRow("Classic Cheese Omelette"), toContain: "Almost makeable")

        app.tabBars.buttons["Pantry"].tap()
        addIngredient(name: "Cheddar", quantity: "100")
        XCTAssertTrue(pantryRow("Cheddar").waitForExistence(timeout: 5))

        openRecipesTab()
        waitForLabel(of: recipeRow("Classic Cheese Omelette"), toContain: "Makeable")
    }

    func test_findSubstitute_showsTheSuggestion() {
        launch(pantry: "Eggs:6:pcs,Milk:500:ml")
        openRecipesTab()

        let omelette = recipeRow("Classic Cheese Omelette")
        XCTAssertTrue(omelette.waitForExistence(timeout: 5))
        omelette.tap()

        let findButton = app.buttons["substitute.find.Cheddar"]
        XCTAssertTrue(findButton.waitForExistence(timeout: 5))
        findButton.tap()

        // the fake service always suggests mozzarella, and we don't have any
        XCTAssertTrue(app.staticTexts["Mozzarella"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Not in your pantry."].exists)
    }

    func test_pantryIdeas_showsSuggestionsBasedOnPantry() {
        launch(pantry: "Eggs:6:pcs")
        openRecipesTab()

        // the sheet loads ideas by itself when it opens, no button to press
        app.buttons["Pantry Ideas"].tap()

        XCTAssertTrue(app.staticTexts["Cheesy Scrambled Eggs"].waitForExistence(timeout: 5))
        // fake model says it needs eggs + cheddar, we only have eggs,
        // so the app (not the model) should split them like this
        XCTAssertTrue(app.staticTexts["From your pantry: Eggs"].exists)
        XCTAssertTrue(app.staticTexts["Missing: Cheddar"].exists)
    }
}
