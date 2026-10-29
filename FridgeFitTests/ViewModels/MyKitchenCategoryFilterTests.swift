//
//  MyKitchenCategoryFilterTests.swift
//  FridgeFitTests
//

import SwiftUI
import UIKit
import XCTest
@testable import FridgeFit

/// The My Fridge category tiles - All, Produce, Proteins, Dairy & Pantry.
///
/// They were drawn as a four-way control but had no action behind them, so
/// tapping one did nothing. These cover the behaviour that fixed it: the
/// selection narrows the list, composes with the storage filter instead of
/// replacing it, and can always be undone.
@MainActor
final class MyKitchenCategoryFilterTests: XCTestCase {

    private func makeViewModel(items: [PantryItem]) async -> MyKitchenViewModel {
        let store = InventoryStore(
            pantryRepository: InMemoryPantryRepository(seedItems: items),
            eventRepository: InMemoryInventoryEventRepository()
        )
        await store.load()
        return MyKitchenViewModel(inventory: store)
    }

    private func item(
        _ name: String,
        category: IngredientCategory,
        storage: StorageLocation = .fridge
    ) -> PantryItem {
        PantryItem(
            ingredient: Ingredient(name: name, category: category),
            quantity: 1,
            unit: .pieces,
            expiryDate: nil,
            storageLocation: storage
        )
    }

    private func names(_ viewModel: MyKitchenViewModel) -> [String] {
        (viewModel.useFirstItems + viewModel.remainingItems).map(\.name).sorted()
    }

    // MARK: - Narrowing

    func test_defaultSelection_showsEveryCategory() async {
        let viewModel = await makeViewModel(items: [
            item("Spinach", category: .produce),
            item("Chicken", category: .meat),
            item("Milk", category: .dairy),
        ])

        XCTAssertEqual(viewModel.selectedCategory, .all)
        XCTAssertEqual(names(viewModel), ["Chicken", "Milk", "Spinach"])
    }

    func test_selectingProduce_narrowsTheListToProduce() async {
        let viewModel = await makeViewModel(items: [
            item("Spinach", category: .produce),
            item("Chicken", category: .meat),
            item("Milk", category: .dairy),
        ])

        viewModel.selectCategory(.produce)

        XCTAssertEqual(names(viewModel), ["Spinach"])
    }

    func test_dairyAndPantry_coversTheWholePantryShelf() async {
        // Grain, spice and uncategorised food have no tile of their own; they
        // are reachable here or nowhere.
        let viewModel = await makeViewModel(items: [
            item("Milk", category: .dairy),
            item("Rice", category: .grain),
            item("Paprika", category: .spice),
            item("Olive oil", category: .other),
            item("Spinach", category: .produce),
        ])

        viewModel.selectCategory(.dairyAndPantry)

        XCTAssertEqual(names(viewModel), ["Milk", "Olive oil", "Paprika", "Rice"])
    }

    func test_everyCategoryIsReachableFromSomeTile() async {
        for category in IngredientCategory.allCases {
            let tiles = InventoryCategorySummary.allCases.filter { $0 != .all }
            XCTAssertTrue(
                tiles.contains { $0.includes(category) },
                "\(category.displayName) can be counted under All but never filtered to"
            )
        }
    }

    // MARK: - Undoing the selection

    func test_tappingTheSelectedTileAgain_returnsToAll() async {
        let viewModel = await makeViewModel(items: [
            item("Spinach", category: .produce),
            item("Chicken", category: .meat),
        ])

        viewModel.selectCategory(.produce)
        viewModel.selectCategory(.produce)

        XCTAssertEqual(viewModel.selectedCategory, .all)
        XCTAssertEqual(names(viewModel), ["Chicken", "Spinach"])
    }

    func test_tappingAll_clearsANarrowedSelection() async {
        let viewModel = await makeViewModel(items: [item("Spinach", category: .produce)])

        viewModel.selectCategory(.proteins)
        viewModel.selectCategory(.all)

        XCTAssertEqual(viewModel.selectedCategory, .all)
    }

    // MARK: - Composing with the storage filter

    func test_categoryAndStorageNarrowTogether() async {
        let viewModel = await makeViewModel(items: [
            item("Chicken", category: .meat, storage: .freezer),
            item("Steak", category: .meat, storage: .fridge),
            item("Peas", category: .produce, storage: .freezer),
        ])

        viewModel.selectFilter(.freezer)
        viewModel.selectCategory(.proteins)

        XCTAssertEqual(names(viewModel), ["Chicken"])
    }

    func test_search_stillAppliesWithinACategory() async {
        let viewModel = await makeViewModel(items: [
            item("Spinach", category: .produce),
            item("Spring onion", category: .produce),
            item("Chicken", category: .meat),
        ])

        viewModel.selectCategory(.produce)
        viewModel.searchText = "spin"

        XCTAssertEqual(names(viewModel), ["Spinach"])
    }

    // MARK: - Keeping the tiles on screen

    func test_anEmptyCategoryKeepsTheDashboardVisible() async {
        // hasResults drives the tiles. If a category with no matches turned
        // it false, the control the user just used would disappear and leave
        // them no way back to All.
        let viewModel = await makeViewModel(items: [item("Spinach", category: .produce)])

        viewModel.selectCategory(.proteins)

        XCTAssertTrue(viewModel.hasResults)
        XCTAssertFalse(viewModel.hasVisibleItems)
    }

    func test_anEmptyPantryHasNoResultsAtAll() async {
        let viewModel = await makeViewModel(items: [])

        XCTAssertFalse(viewModel.hasResults)
        XCTAssertFalse(viewModel.hasVisibleItems)
    }

    // MARK: - Tile counts

    func test_tileCountsMatchWhatTappingTheTileShows() async {
        let viewModel = await makeViewModel(items: [
            item("Spinach", category: .produce),
            item("Carrot", category: .produce),
            item("Chicken", category: .meat),
        ])

        XCTAssertEqual(viewModel.itemCount(for: .all), 3)
        XCTAssertEqual(viewModel.itemCount(for: .produce), 2)

        viewModel.selectCategory(.produce)
        XCTAssertEqual(names(viewModel).count, viewModel.itemCount(for: .produce))
    }

    func test_tileCountsRespectTheStorageFilter() async {
        // A tile reading "2 items" that shows one after a tap would be lying
        // about the set the user is actually looking at.
        let viewModel = await makeViewModel(items: [
            item("Spinach", category: .produce, storage: .fridge),
            item("Peas", category: .produce, storage: .freezer),
        ])

        viewModel.selectFilter(.freezer)

        XCTAssertEqual(viewModel.itemCount(for: .produce), 1)
    }

    // MARK: - Empty state wording

    func test_aNarrowedCategoryIsNotTreatedAsAnEmptyKitchen() async {
        let viewModel = await makeViewModel(items: [item("Spinach", category: .produce)])

        viewModel.selectCategory(.proteins)

        XCTAssertFalse(viewModel.isShowingDefaultEmptyState)
    }

    // MARK: - Rendering

    /// Evaluates the dashboard's body against a real pantry, so a tile that
    /// traps or mis-lays-out fails here rather than on screen.
    ///
    /// It does not exercise the tap itself - this project has no UI test
    /// target, so that stays manual, as `RecommendationViewRenderingTests`
    /// notes for the same reason. What it covers is everything the tiles
    /// compute on the way to being drawn.
    func test_theDashboardRendersWithTheCategoryTilesInPlace() async {
        let store = InventoryStore(
            pantryRepository: InMemoryPantryRepository(seedItems: [
                item("Spinach", category: .produce),
                item("Chicken", category: .meat, storage: .freezer),
                item("Rice", category: .grain, storage: .pantry),
            ]),
            eventRepository: InMemoryInventoryEventRepository()
        )
        await store.load()

        let view = NavigationStack {
            MyKitchenView(
                inventory: store,
                scannerViewModel: ReceiptScannerViewModel(
                    textRecognizer: MockReceiptTextRecognizer(lines: SampleReceiptPreviewData.lines),
                    interpreter: MockReceiptIngredientInterpreter(),
                    pantryRepository: InMemoryPantryRepository()
                ),
                isPresentingSmartScan: .constant(false)
            )
        }

        let size = CGSize(width: 393, height: 852)
        let controller = UIHostingController(rootView: view.frame(width: size.width, height: size.height))
        controller.view.bounds = CGRect(origin: .zero, size: size)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            controller.view.layer.render(in: context.cgContext)
        }

        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }
}
