import Foundation
import XCTest
@testable import FridgeFit

final class KitchenImpactSummaryTests: XCTestCase {
    func test_calculate_countsOnlyFinishedAndDiscardedEventsInCurrentMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(2026, 10, 19, calendar: calendar)
        let itemID = UUID()
        let events = [
            InventoryEvent(pantryItemID: itemID, itemName: "Spinach", kind: .finished, date: date(2026, 10, 2, calendar: calendar)),
            InventoryEvent(pantryItemID: itemID, itemName: "Spinach", kind: .discarded, date: date(2026, 10, 3, calendar: calendar)),
            InventoryEvent(pantryItemID: itemID, itemName: "Spinach", kind: .finished, date: date(2026, 9, 30, calendar: calendar)),
            InventoryEvent(pantryItemID: itemID, itemName: "Spinach", kind: .added, date: date(2026, 10, 4, calendar: calendar)),
        ]

        let summary = KitchenImpactSummary.calculate(events: events, now: now, calendar: calendar)

        XCTAssertEqual(summary.finishedThisMonth, 1)
        XCTAssertEqual(summary.discardedThisMonth, 1)
    }

    func test_calculate_doesNotMisrepresentActivityAsRescueOrSavings() {
        let event = InventoryEvent(
            pantryItemID: UUID(),
            itemName: "Mushrooms",
            kind: .finished,
            date: .now
        )

        let summary = KitchenImpactSummary.calculate(events: [event])

        XCTAssertNil(summary.rescuedItems)
        XCTAssertNil(summary.grocerySavings)
        XCTAssertNil(summary.preventedCO2eKilograms)
        XCTAssertNil(summary.pantryEfficiencyPercent)
        XCTAssertNil(summary.zeroWasteStreakWeeks)
        XCTAssertTrue(summary.frequentlyRescuedStaples.isEmpty)
        XCTAssertTrue(summary.weeklyRecoveryPercentages.isEmpty)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
