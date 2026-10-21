//
//  AppNavigationStateTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class AppNavigationStateTests: XCTestCase {
    func testFivePrimaryTabsRemainAvailable() {
        XCTAssertEqual(Set(AppTab.allCases), [.home, .kitchen, .recipes, .discover, .profile])
    }

    func testMyFridgeShortcutSelectsKitchenWithoutPresentingScanner() {
        var navigation = AppNavigationState()

        navigation.openMyFridge()

        XCTAssertEqual(navigation.selectedTab, .kitchen)
        XCTAssertFalse(navigation.isPresentingSmartScan)
    }

    func testSmartScanShortcutSelectsKitchenAndPresentsOneBooleanSession() {
        var navigation = AppNavigationState()

        navigation.openSmartScan()
        navigation.openSmartScan()

        XCTAssertEqual(navigation.selectedTab, .kitchen)
        XCTAssertTrue(navigation.isPresentingSmartScan)
    }

    func testBrowseRecipesSelectsRecipesAndRepeatedRequestsDoNotStackRoutes() {
        var navigation = AppNavigationState()

        navigation.browseRecipes()
        navigation.browseRecipes()

        XCTAssertEqual(navigation.selectedTab, .recipes)
        XCTAssertTrue(navigation.isBrowsingRecipes)
    }
}
