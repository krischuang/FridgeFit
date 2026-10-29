//
//  TestSupport.swift
//  FridgeFitTests
//

import Foundation
import XCTest
@testable import FridgeFit

/// `XCTAssertThrowsError` for an `async` call.
///
/// Needed because the FridgeFunds writes became `async throws` when they
/// started reporting what actually happened to them, and `XCTAssertThrowsError`
/// cannot await. The expectations are unchanged - this only moves them across
/// the `await`.
func assertThrowsAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: String = "Expected an error to be thrown",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail(message, file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

/// A `BudgetStore` whose writes fail, for the propagation tests.
///
/// The point of the refactor is that a storage failure reaches the user, and
/// nothing can demonstrate that with a store that always succeeds.
@MainActor
final class FailingBudgetStore: BudgetStore {
    struct WriteRefused: Error, Equatable {}

    private let inner: InMemoryBudgetStore
    /// Incremented on every attempted write, so a test can prove a retry
    /// issued exactly one more write rather than duplicating.
    private(set) var attemptedWrites = 0
    var shouldFail: Bool

    init(budget: FoodBudget? = nil, shouldFail: Bool = true) {
        self.inner = InMemoryBudgetStore(budget: budget)
        self.shouldFail = shouldFail
    }

    func load() async throws {}

    func activeBudget() -> FoodBudget? { inner.activeBudget() }

    @discardableResult
    func saveBudget(_ budget: FoodBudget) async throws -> FundsWriteOutcome {
        attemptedWrites += 1
        if shouldFail { throw WriteRefused() }
        return try await inner.saveBudget(budget)
    }

    func allSpends() -> [GrocerySpend] { inner.allSpends() }

    @discardableResult
    func addSpend(_ spend: GrocerySpend) async throws -> FundsWriteOutcome {
        attemptedWrites += 1
        if shouldFail { throw WriteRefused() }
        return try await inner.addSpend(spend)
    }

    func allWasteCosts() -> [WastedFoodCost] { inner.allWasteCosts() }

    @discardableResult
    func addWasteCost(_ cost: WastedFoodCost) async throws -> FundsWriteOutcome {
        attemptedWrites += 1
        if shouldFail { throw WriteRefused() }
        return try await inner.addWasteCost(cost)
    }

    func wasteAlreadyRecorded(for itemID: PantryItemID, on day: Date) -> Bool {
        inner.wasteAlreadyRecorded(for: itemID, on: day)
    }
}

/// An `ItemPriceStore` that reports a queued-but-unconfirmed write, the way
/// Firestore does on an offline device.
@MainActor
final class PendingSyncItemPriceStore: ItemPriceStore {
    private let inner = InMemoryItemPriceStore()

    func info(for itemID: PantryItemID) -> ItemPriceInfo? { inner.info(for: itemID) }

    @discardableResult
    func save(_ info: ItemPriceInfo) async throws -> FundsWriteOutcome {
        _ = try await inner.save(info)
        return .pendingSync
    }
}

/// A `PriceBookStore` that reports a queued-but-unconfirmed write.
@MainActor
final class PendingSyncPriceBookStore: PriceBookStore {
    private let inner = InMemoryPriceBookStore()

    func entry(forIngredientNamed name: String) -> PriceBookEntry? {
        inner.entry(forIngredientNamed: name)
    }

    @discardableResult
    func record(_ entry: PriceBookEntry) async throws -> FundsWriteOutcome {
        _ = try await inner.record(entry)
        return .pendingSync
    }
}

/// An `ItemPriceStore` whose writes always fail.
@MainActor
final class FailingItemPriceStore: ItemPriceStore {
    struct WriteRefused: Error, Equatable {}

    func info(for itemID: PantryItemID) -> ItemPriceInfo? { nil }

    @discardableResult
    func save(_ info: ItemPriceInfo) async throws -> FundsWriteOutcome {
        throw WriteRefused()
    }
}

// fixed dates so tests don't depend on what day they actually run. day(0) is the
// anchor itself, positive offsets move forward from there.
enum TestDates {
    static let anchor: Date = {
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 1
        components.hour = 12
        return Calendar.current.date(from: components)!
    }()

    static func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: anchor)!
    }
}

// shorthand for an AUD amount
func aud(_ amount: Decimal) -> Money {
    Money(amount, .aud)
}

// weekly budget starting at TestDates.anchor
func makeWeeklyBudget(limit: Decimal, currency: Currency = .aud) -> FoodBudget {
    FoodBudget(limit: Money(limit, currency), cadence: .weekly, startDate: TestDates.anchor)
}

// pantry with a single item, id "test-item", for RecordDiscardedItemCostUseCase tests
func makePantry(unitCost: Money?,
                 quantity: Double = 10,
                 unit: String = "each",
                 name: String = "Test Item") -> PantryReading {
    let item = PantryItemSnapshot(id: PantryItemID("test-item"),
                                  name: name,
                                  quantity: quantity,
                                  unit: unit,
                                  expiryDate: nil,
                                  unitCost: unitCost)
    return InMemoryPantryReading(items: [item])
}
