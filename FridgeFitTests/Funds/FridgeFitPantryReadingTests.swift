//
//  FridgeFitPantryReadingTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

// the bridge from FridgeFit's pantry to FridgeFunds. main things to check: it shows
// the real pantry, prices/expiry come from the price store, and it never writes back.
@MainActor
final class FridgeFitPantryReadingTests: XCTestCase {
    private let milk = PantryItem(ingredient: Ingredient(name: "Milk", category: .dairy), quantity: 2, unit: .liters)
    private let eggs = PantryItem(ingredient: Ingredient(name: "Eggs"), quantity: 6, unit: .pieces)

    func test_allItems_isEmpty_untilRefreshed() async throws {
        let reading = FridgeFitPantryReading(repository: InMemoryPantryRepository(seedItems: [milk]),
                                             priceStore: InMemoryItemPriceStore())

        XCTAssertTrue(reading.allItems().isEmpty)
        try await reading.refresh()
        XCTAssertEqual(reading.allItems().map(\.name), ["Milk"])
    }

    func test_snapshot_usesPantryIdNameQuantityAndUnitSymbol() async throws {
        let reading = FridgeFitPantryReading(repository: InMemoryPantryRepository(seedItems: [milk]),
                                             priceStore: InMemoryItemPriceStore())
        try await reading.refresh()

        let snapshot = try XCTUnwrap(reading.allItems().first)
        XCTAssertEqual(snapshot.id, PantryItemID(milk.id.uuidString))
        XCTAssertEqual(snapshot.quantity, 2)
        XCTAssertEqual(snapshot.unit, "L")
        // no price saved yet, so nothing to value
        XCTAssertNil(snapshot.unitCost)
        XCTAssertNil(snapshot.expiryDate)
    }

    func test_priceAndExpiry_comeFromThePriceStore_withoutRefetching() async throws {
        let prices = InMemoryItemPriceStore()
        let reading = FridgeFitPantryReading(repository: InMemoryPantryRepository(seedItems: [milk, eggs]),
                                             priceStore: prices)
        try await reading.refresh()

        let id = FridgeFitPantryReading.id(for: eggs)
        try await prices.save(ItemPriceInfo(pantryItemID: id, unitCost: Money(Decimal(string: "0.5")!, .aud), expiryDate: TestDates.day(3)))

        let snapshot = try XCTUnwrap(reading.item(withID: id))
        XCTAssertEqual(snapshot.unitCost, Money(Decimal(string: "0.5")!, .aud))
        XCTAssertEqual(snapshot.lineValue, Money(3, .aud))
        XCTAssertEqual(snapshot.expiryDate, TestDates.day(3))
    }

    func test_expiry_comesFromThePantry_beforeOurOldCopy() async throws {
        let yoghurt = PantryItem(ingredient: Ingredient(name: "Yoghurt"), quantity: 1, unit: .pieces,
                                 expiryDate: TestDates.day(2))
        let prices = InMemoryItemPriceStore()
        let reading = FridgeFitPantryReading(repository: InMemoryPantryRepository(seedItems: [yoghurt]),
                                             priceStore: prices)
        try await reading.refresh()
        // an old FridgeFunds-side expiry from before the pantry had the field
        try await prices.save(ItemPriceInfo(pantryItemID: FridgeFitPantryReading.id(for: yoghurt), expiryDate: TestDates.day(9)))

        XCTAssertEqual(reading.allItems().first?.expiryDate, TestDates.day(2))
    }

    func test_oldStoredExpiry_isStillUsed_whenThePantryHasNone() async throws {
        let prices = InMemoryItemPriceStore()
        let reading = FridgeFitPantryReading(repository: InMemoryPantryRepository(seedItems: [milk]),
                                             priceStore: prices)
        try await reading.refresh()
        try await prices.save(ItemPriceInfo(pantryItemID: FridgeFitPantryReading.id(for: milk), expiryDate: TestDates.day(4)))

        XCTAssertEqual(reading.allItems().first?.expiryDate, TestDates.day(4))
    }

    func test_refresh_picksUpPantryChanges() async throws {
        let repository = InMemoryPantryRepository(seedItems: [milk])
        let reading = FridgeFitPantryReading(repository: repository, priceStore: InMemoryItemPriceStore())
        try await reading.refresh()

        try await repository.add(eggs)
        try await reading.refresh()

        XCTAssertEqual(Set(reading.allItems().map(\.name)), ["Milk", "Eggs"])
    }

    func test_wasteUseCase_doesNotTouchThePantry() async throws {
        let repository = InMemoryPantryRepository(seedItems: [eggs])
        let prices = InMemoryItemPriceStore()
        let reading = FridgeFitPantryReading(repository: repository, priceStore: prices)
        try await reading.refresh()
        let id = FridgeFitPantryReading.id(for: eggs)
        try await prices.save(ItemPriceInfo(pantryItemID: id, unitCost: Money(1, .aud)))

        let useCase = RecordDiscardedItemCostUseCase(pantry: reading, budgetStore: InMemoryBudgetStore())
        let recorded = try await useCase.execute(itemID: id, quantityDiscarded: 2, reason: .spoiled)

        XCTAssertEqual(recorded.cost.lostAmount, Money(2, .aud))
        // still 6 eggs in FridgeFit's pantry - FridgeFunds only reads it
        let stored = try await repository.fetchAll()
        XCTAssertEqual(stored.first?.quantity, 6)
    }
}
