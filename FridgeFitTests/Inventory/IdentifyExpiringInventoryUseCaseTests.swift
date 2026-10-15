//
//  IdentifyExpiringInventoryUseCaseTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class IdentifyExpiringInventoryUseCaseTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private lazy var now = calendar.date(
        from: DateComponents(year: 2026, month: 6, day: 15, hour: 9)
    )!

    private lazy var useCase = IdentifyExpiringInventoryUseCase(now: now, calendar: calendar)

    private func item(
        _ name: String,
        daysToExpiry: Int? = nil,
        storage: StorageLocation? = .fridge,
        category: IngredientCategory = .produce,
        quantity: Double = 1,
        lowStockThreshold: Double? = nil
    ) -> PantryItem {
        PantryItem(
            ingredient: Ingredient(name: name, category: category),
            quantity: quantity,
            unit: .pieces,
            expiryDate: daysToExpiry.map { calendar.date(byAdding: .day, value: $0, to: now)! },
            storageLocation: storage,
            lowStockThreshold: lowStockThreshold
        )
    }

    // MARK: - Use First window

    func test_useFirst_includesExpiredThroughThreeDaysOut() {
        let items = [
            item("Expired", daysToExpiry: -2),
            item("Today", daysToExpiry: 0),
            item("Tomorrow", daysToExpiry: 1),
            item("Three days", daysToExpiry: 3),
        ]

        let result = useCase.execute(items: items)

        XCTAssertEqual(result.map(\.name), ["Expired", "Today", "Tomorrow", "Three days"])
    }

    func test_useFirst_excludesFoodFurtherOut() {
        let items = [item("This week", daysToExpiry: 5), item("Next month", daysToExpiry: 40)]

        XCTAssertTrue(useCase.execute(items: items).isEmpty)
    }

    func test_useFirst_excludesUndatedFood() {
        // Untracked is not urgent. Treating it as urgent would fill the
        // section with everything the user never dated.
        XCTAssertTrue(useCase.execute(items: [item("Rice", daysToExpiry: nil)]).isEmpty)
    }

    func test_useFirst_ordersMostUrgentFirst() {
        let items = [
            item("Three days", daysToExpiry: 3),
            item("Expired", daysToExpiry: -1),
            item("Tomorrow", daysToExpiry: 1),
        ]

        XCTAssertEqual(useCase.execute(items: items).map(\.name), ["Expired", "Tomorrow", "Three days"])
    }

    func test_useFirst_breaksTiesAlphabetically() {
        let items = [item("Zucchini", daysToExpiry: 1), item("Apple", daysToExpiry: 1)]

        XCTAssertEqual(useCase.execute(items: items).map(\.name), ["Apple", "Zucchini"])
    }

    // MARK: - The two sections together cover everything

    func test_remainder_holdsEverythingNotInUseFirst() {
        let items = [
            item("Urgent", daysToExpiry: 1),
            item("Later", daysToExpiry: 20),
            item("Undated", daysToExpiry: nil),
        ]

        XCTAssertEqual(useCase.execute(items: items).map(\.name), ["Urgent"])
        XCTAssertEqual(Set(useCase.remainder(items: items).map(\.name)), ["Later", "Undated"])
    }

    func test_theTwoSections_partitionTheMatchingSet_withNoItemLostOrDuplicated() {
        let items = (0..<12).map { index in
            item("Item \(index)", daysToExpiry: index % 4 == 0 ? nil : index - 2)
        }

        let urgent = useCase.execute(items: items)
        let rest = useCase.remainder(items: items)

        XCTAssertEqual(urgent.count + rest.count, items.count)
        XCTAssertTrue(Set(urgent.map(\.id)).isDisjoint(with: Set(rest.map(\.id))))
    }

    // MARK: - Filtering

    func test_storageFilter_narrowsToOneArea() {
        let items = [
            item("Milk", daysToExpiry: 1, storage: .fridge),
            item("Peas", daysToExpiry: 1, storage: .freezer),
        ]

        XCTAssertEqual(useCase.execute(items: items, filter: .fridge).map(\.name), ["Milk"])
        XCTAssertEqual(useCase.execute(items: items, filter: .freezer).map(\.name), ["Peas"])
        XCTAssertEqual(useCase.execute(items: items, filter: .all).count, 2)
    }

    func test_storageFilter_findsUnlocatedItemsUnderPantry() {
        // Scanner- and camera-added items have no recorded location; they
        // read as pantry rather than vanishing from every filter.
        let items = [item("Scanned", daysToExpiry: 1, storage: nil)]

        XCTAssertEqual(useCase.execute(items: items, filter: .pantry).map(\.name), ["Scanned"])
        XCTAssertTrue(useCase.execute(items: items, filter: .freezer).isEmpty)
    }

    func test_search_matchesNameCaseInsensitively() {
        let items = [item("Chicken Breast", daysToExpiry: 1), item("Spinach", daysToExpiry: 1)]

        XCTAssertEqual(useCase.execute(items: items, searchText: "chicken").map(\.name), ["Chicken Breast"])
    }

    func test_search_alsoMatchesCategory() {
        // So "dairy" finds the milk without the user remembering the name
        // they gave it.
        let items = [
            item("Milk", daysToExpiry: 1, category: .dairy),
            item("Carrot", daysToExpiry: 1, category: .produce),
        ]

        XCTAssertEqual(useCase.execute(items: items, searchText: "Dairy").map(\.name), ["Milk"])
    }

    func test_search_ignoresSurroundingWhitespace() {
        let items = [item("Milk", daysToExpiry: 1)]

        XCTAssertEqual(useCase.execute(items: items, searchText: "  milk  ").count, 1)
        XCTAssertEqual(useCase.execute(items: items, searchText: "   ").count, 1)
    }
}
