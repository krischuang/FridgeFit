import Foundation
import XCTest
@testable import FridgeFit

final class KitchenActivitySummaryTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    // MARK: - Month counts

    func test_calculate_countsOnlyFinishedAndDiscardedEventsInCurrentMonth() {
        let now = date(2026, 10, 19)
        let itemID = UUID()
        let events = [
            event(itemID, "Spinach", .finished, date(2026, 10, 2)),
            event(itemID, "Spinach", .discarded, date(2026, 10, 3)),
            event(itemID, "Spinach", .finished, date(2026, 9, 30)),
            event(itemID, "Spinach", .added, date(2026, 10, 4)),
        ]

        let summary = KitchenActivitySummary.calculate(events: events, now: now, calendar: calendar)

        XCTAssertEqual(summary.finishedThisMonth, 1)
        XCTAssertEqual(summary.discardedThisMonth, 1)
    }

    /// A month boundary must not leak: the same event set read on the 1st of
    /// November counts nothing from October.
    func test_calculate_resetsAtTheMonthBoundary() {
        let events = [
            event(UUID(), "Spinach", .finished, date(2026, 10, 31)),
            event(UUID(), "Milk", .discarded, date(2026, 10, 31)),
        ]

        let october = KitchenActivitySummary.calculate(events: events, now: date(2026, 10, 31), calendar: calendar)
        let november = KitchenActivitySummary.calculate(events: events, now: date(2026, 11, 1), calendar: calendar)

        XCTAssertEqual(october.finishedThisMonth, 1)
        XCTAssertEqual(october.discardedThisMonth, 1)
        XCTAssertEqual(november.finishedThisMonth, 0)
        XCTAssertEqual(november.discardedThisMonth, 0)
        XCTAssertNil(november.pantryEfficiencyPercent)
    }

    // MARK: - What stays unavailable

    func test_calculate_doesNotMisrepresentActivityAsRescueSavingsOrEmissions() {
        let summary = KitchenActivitySummary.calculate(
            events: [event(UUID(), "Mushrooms", .finished, date(2026, 10, 10))],
            now: date(2026, 10, 19),
            calendar: calendar
        )

        XCTAssertNil(summary.rescuedItems, "An event keeps no expiry date, so nothing can be called rescued in time.")
        XCTAssertNil(summary.grocerySavings, "An event keeps no price.")
        XCTAssertNil(summary.preventedCO2eKilograms, "FridgeFit records no emissions factors.")
    }

    // MARK: - Pantry efficiency

    func test_pantryEfficiency_isTheShareOfOutcomesThatWereFinished() {
        let now = date(2026, 10, 19)
        let events = (0..<3).map { event(UUID(), "Item \($0)", .finished, date(2026, 10, 5)) }
            + [event(UUID(), "Binned", .discarded, date(2026, 10, 6))]

        let summary = KitchenActivitySummary.calculate(events: events, now: now, calendar: calendar)

        XCTAssertEqual(summary.pantryEfficiencyPercent ?? 0, 75, accuracy: 0.0001)
    }

    func test_pantryEfficiency_isUnavailableRatherThanZero_whenNothingLeftTheKitchen() {
        let summary = KitchenActivitySummary.calculate(
            events: [event(UUID(), "Spinach", .added, date(2026, 10, 5))],
            now: date(2026, 10, 19),
            calendar: calendar
        )

        XCTAssertNil(summary.pantryEfficiencyPercent)
    }

    func test_pantryEfficiency_isZero_whenEverythingRecordedWasBinned() {
        let summary = KitchenActivitySummary.calculate(
            events: [event(UUID(), "Spinach", .discarded, date(2026, 10, 5))],
            now: date(2026, 10, 19),
            calendar: calendar
        )

        XCTAssertEqual(summary.pantryEfficiencyPercent, 0, "Zero is a real measurement here, not missing data.")
    }

    // MARK: - Weekly recovery

    func test_weeklyRecovery_coversFourWeeksOldestFirst() {
        let summary = KitchenActivitySummary.calculate(events: [], now: date(2026, 10, 19), calendar: calendar)

        XCTAssertEqual(summary.weeklyRecovery.map(\.label), ["W1", "W2", "W3", "W4"])
        XCTAssertTrue(summary.weeklyRecovery.allSatisfy { $0.percent == nil })
        XCTAssertTrue(
            zip(summary.weeklyRecovery, summary.weeklyRecovery.dropFirst()).allSatisfy { $0.weekStart < $1.weekStart }
        )
    }

    func test_weeklyRecovery_scoresEachWeekAgainstItsOwnOutcomes() {
        let now = date(2026, 10, 19) // a Monday
        let thisWeek = date(2026, 10, 20)
        let lastWeek = date(2026, 10, 14)

        let events = [
            event(UUID(), "A", .finished, thisWeek),
            event(UUID(), "B", .finished, thisWeek),
            event(UUID(), "C", .finished, lastWeek),
            event(UUID(), "D", .discarded, lastWeek),
        ]

        let summary = KitchenActivitySummary.calculate(events: events, now: now, calendar: calendar)
        let weeks = summary.weeklyRecovery

        XCTAssertEqual(weeks.count, 4)
        XCTAssertEqual(weeks[3].percent ?? 0, 100, accuracy: 0.0001, "The current week had two finishes and no discards.")
        XCTAssertEqual(weeks[2].percent ?? 0, 50, accuracy: 0.0001, "Last week was one of each.")
        XCTAssertNil(weeks[0].percent, "Nothing was recorded four weeks ago.")
        XCTAssertNil(weeks[1].percent)
    }

    // MARK: - Zero-waste streak

    func test_zeroWasteStreak_isUnavailableWithNoHistory() {
        let summary = KitchenActivitySummary.calculate(events: [], now: date(2026, 10, 19), calendar: calendar)
        XCTAssertNil(summary.zeroWasteStreakWeeks)
    }

    func test_zeroWasteStreak_isNotCreditedForWeeksBeforeTheFirstRecordedOutcome() {
        let summary = KitchenActivitySummary.calculate(
            events: [event(UUID(), "Spinach", .finished, date(2026, 10, 19))],
            now: date(2026, 10, 19),
            calendar: calendar
        )

        XCTAssertEqual(summary.zeroWasteStreakWeeks, 1, "History starts this week, so the streak cannot be longer than this week.")
    }

    /// Anchored to the calendar's own week boundaries rather than to
    /// hand-picked dates, so the expectation holds whether weeks start on a
    /// Sunday or a Monday.
    func test_zeroWasteStreak_stopsAtTheMostRecentDiscard() {
        let now = date(2026, 10, 19)
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start

        func streak(withDiscardWeeksBack weeksBack: Int) -> Int? {
            let discardWeekStart = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: thisWeekStart)!
            let discardedOn = calendar.date(byAdding: .hour, value: 36, to: discardWeekStart)!
            let events = [
                event(UUID(), "Old", .finished, date(2026, 9, 1)),
                event(UUID(), "Binned", .discarded, discardedOn),
                event(UUID(), "Eaten", .finished, now),
            ]
            return KitchenActivitySummary.calculate(events: events, now: now, calendar: calendar).zeroWasteStreakWeeks
        }

        XCTAssertEqual(streak(withDiscardWeeksBack: 1), 1, "Only this week is clean.")
        XCTAssertEqual(streak(withDiscardWeeksBack: 2), 2, "This week and last week are clean.")
        XCTAssertEqual(streak(withDiscardWeeksBack: 0), 0, "Something was binned this week.")
    }

    func test_zeroWasteStreak_isZero_whenSomethingWasBinnedThisWeek() {
        let summary = KitchenActivitySummary.calculate(
            events: [event(UUID(), "Binned", .discarded, date(2026, 10, 19))],
            now: date(2026, 10, 19),
            calendar: calendar
        )

        XCTAssertEqual(summary.zeroWasteStreakWeeks, 0)
    }

    // MARK: - Most finished staples

    func test_mostFinishedStaples_rankByCountAndIgnoreOtherEventKinds() {
        let now = date(2026, 10, 19)
        let events = [
            event(UUID(), "Spinach", .finished, date(2026, 10, 2)),
            event(UUID(), "spinach", .finished, date(2026, 10, 5)),
            event(UUID(), "Eggs", .finished, date(2026, 10, 6)),
            event(UUID(), "Milk", .discarded, date(2026, 10, 7)),
            event(UUID(), "Milk", .added, date(2026, 10, 8)),
        ]

        let staples = KitchenActivitySummary.calculate(events: events, now: now, calendar: calendar).mostFinishedStaples

        XCTAssertEqual(staples.map(\.name), ["spinach", "Eggs"], "Case-insensitive grouping, most recent spelling wins.")
        XCTAssertEqual(staples.map(\.timesFinished), [2, 1])
    }

    func test_mostFinishedStaples_areCappedAtTheDisplayLimit() {
        let events = (0..<10).map { event(UUID(), "Item \($0)", .finished, date(2026, 10, 5)) }

        let staples = KitchenActivitySummary.calculate(events: events, now: date(2026, 10, 19), calendar: calendar)
            .mostFinishedStaples

        XCTAssertEqual(staples.count, KitchenActivitySummary.stapleLimit)
    }

    // MARK: - Helpers

    private func event(_ id: UUID, _ name: String, _ kind: InventoryEventKind, _ date: Date) -> InventoryEvent {
        InventoryEvent(pantryItemID: id, itemName: name, kind: kind, date: date)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
