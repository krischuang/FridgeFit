//
//  AppNavigationStateTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class AppNavigationStateTests: XCTestCase {
    func testFivePrimaryTabsRemainAvailable() {
        XCTAssertEqual(Set(AppTab.allCases), [.home, .kitchen, .recipes, .discover, .profile])
        XCTAssertEqual(AppTab.navigationOrder, [.kitchen, .recipes, .home, .discover, .profile])
    }

    func testHomeRemainsTheDefaultTab() {
        XCTAssertEqual(AppNavigationState().selectedTab, .home)
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

    func testFindRecipesSelectsRecipesWithoutCatalogueState() {
        var navigation = AppNavigationState()
        navigation.browseRecipes()

        navigation.findRecipes()

        XCTAssertEqual(navigation.selectedTab, .recipes)
        XCTAssertFalse(navigation.isBrowsingRecipes)
    }

    func testDiscoverSelectionUsesSharedNavigationState() {
        var navigation = AppNavigationState()

        navigation.openDiscover()

        XCTAssertEqual(navigation.selectedTab, .discover)
    }
}
