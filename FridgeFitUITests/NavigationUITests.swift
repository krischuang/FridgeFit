//
//  NavigationUITests.swift
//  FridgeFitUITests
//

import XCTest

// tab layout after merging Kitchen + Discover + Budget. iPhone only shows five
// tabs before hiding the rest under "More", so Profile lives on the Pantry tab.
final class NavigationUITests: FridgeFitUITestCase {

    func test_fiveTabs_noMoreTab() {
        launch()

        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 15))
        for name in ["Pantry", "Kitchen", "Recipes", "Discover", "Budget"] {
            XCTAssertTrue(tabs.buttons[name].exists, "\(name) tab missing")
        }
        XCTAssertFalse(tabs.buttons["More"].exists)
    }

    func test_profileButton_opensProfile_andDoneCloses() {
        launch()

        let button = app.buttons["profileButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()

        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Sign Out"].exists)

        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Pantry"].waitForExistence(timeout: 5))
    }
}
