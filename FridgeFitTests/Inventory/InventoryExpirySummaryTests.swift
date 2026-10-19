//
//  InventoryExpirySummaryTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class InventoryExpirySummaryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 15))!
    }

    private func item(named name: String, daysFromNow: Int?) -> PantryItem {
        PantryItem(
            ingredient: Ingredient(name: name, category: .other),
            quantity: 1,
            unit: .pieces,
            expiryDate: daysFromNow.flatMap { calendar.date(byAdding: .day, value: $0, to: now) }
        )
    }

    func testSummaryPartitionsExpiredExpiringAndFreshWithoutDoubleCounting() {
        let items = [
            item(named: "Past", daysFromNow: -1),
            item(named: "Today", daysFromNow: 0),
            item(named: "Tomorrow", daysFromNow: 1),
            item(named: "Later", daysFromNow: 7),
            item(named: "Undated", daysFromNow: nil),
        ]

        let summary = InventoryExpirySummary(items: items, now: now, calendar: calendar)

        XCTAssertEqual(summary.expiredItems.map(\.name), ["Past"])
        XCTAssertEqual(Set(summary.expiringItems.map(\.name)), ["Today", "Tomorrow"])
        XCTAssertEqual(Set(summary.freshItems.map(\.name)), ["Later", "Undated"])
        XCTAssertEqual(
            summary.freshItems.count + summary.expiringItems.count + summary.expiredItems.count,
            items.count
        )
    }

    func testSummaryHasZeroExpiredItemsWhenEveryItemIsCurrent() {
        let items = [
            item(named: "Today", daysFromNow: 0),
            item(named: "Later", daysFromNow: 8),
            item(named: "Undated", daysFromNow: nil),
        ]

        let summary = InventoryExpirySummary(items: items, now: now, calendar: calendar)

        XCTAssertTrue(summary.expiredItems.isEmpty)
        XCTAssertEqual(summary.expiringItems.count, 1)
        XCTAssertEqual(summary.freshItems.count, 2)
    }

    func testSummaryUsesCalendarDayBoundaryInTheSuppliedTimezone() {
        let earlierToday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 1))!
        let item = PantryItem(
            ingredient: Ingredient(name: "Milk", category: .dairy),
            quantity: 1,
            unit: .liters,
            expiryDate: earlierToday
        )

        let summary = InventoryExpirySummary(items: [item], now: now, calendar: calendar)

        XCTAssertTrue(summary.expiredItems.isEmpty)
        XCTAssertEqual(summary.expiringItems.map(\.name), ["Milk"])
    }
}
