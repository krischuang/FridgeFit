//
//  ExpiryServiceTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class ExpiryServiceTests: XCTestCase {
    /// A fixed "now" so the day boundaries are testable without waiting for
    /// midnight. Mid-afternoon on purpose: urgency is measured in whole days
    /// from the start of today, not in elapsed hours.
    private let now = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 6, day: 15, hour: 14, minute: 30)
    )!
    private var calendar: Calendar { Calendar(identifier: .gregorian) }

    private func date(daysFromNow days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: now)!
    }

    private func state(daysFromNow days: Int) -> ExpiryState? {
        ExpiryService.state(for: date(daysFromNow: days), now: now, calendar: calendar)
    }

    func test_state_isNil_whenExpiryIsNotTracked() {
        // Not the same as "expires today" - an undated item is untracked,
        // and nothing is allowed to invent a date for it.
        XCTAssertNil(ExpiryService.state(for: nil, now: now, calendar: calendar))
    }

    func test_state_reportsExpired_forAPastDate() {
        let expired = state(daysFromNow: -1)
        XCTAssertEqual(expired?.urgency, .expired)
        XCTAssertEqual(expired?.title, "Expired")
        XCTAssertEqual(expired?.daysUntilExpiry, -1)
    }

    func test_state_reportsToday_forLaterTheSameDay() {
        let today = state(daysFromNow: 0)
        XCTAssertEqual(today?.urgency, .today)
        XCTAssertEqual(today?.title, "Today")
    }

    func test_state_reportsTomorrow() {
        XCTAssertEqual(state(daysFromNow: 1)?.urgency, .tomorrow)
        XCTAssertEqual(state(daysFromNow: 1)?.title, "Tomorrow")
    }

    func test_state_reportsSoon_withinThreeDays() {
        XCTAssertEqual(state(daysFromNow: 2)?.urgency, .soon)
        XCTAssertEqual(state(daysFromNow: 3)?.urgency, .soon)
        XCTAssertEqual(state(daysFromNow: 3)?.title, "3 days")
    }

    func test_state_reportsThisWeek_betweenFourAndSevenDays() {
        XCTAssertEqual(state(daysFromNow: 4)?.urgency, .thisWeek)
        XCTAssertEqual(state(daysFromNow: 7)?.urgency, .thisWeek)
    }

    func test_state_reportsNoUrgency_beyondAWeek() {
        // Spelled out rather than `.none`: against an optional, a bare
        // `.none` resolves to `Optional.none` and the assertion would be
        // checking for nil instead of for the urgency case.
        XCTAssertEqual(state(daysFromNow: 8)?.urgency, ExpiryUrgency.none)
    }

    func test_shouldPrioritise_coversExpiredThroughThreeDays_andStopsThere() {
        // The "Use First" window. Four days out is deliberately excluded:
        // surfacing a week of food as urgent makes the section meaningless.
        XCTAssertEqual(state(daysFromNow: -1)?.shouldPrioritise, true)
        XCTAssertEqual(state(daysFromNow: 0)?.shouldPrioritise, true)
        XCTAssertEqual(state(daysFromNow: 1)?.shouldPrioritise, true)
        XCTAssertEqual(state(daysFromNow: 3)?.shouldPrioritise, true)
        XCTAssertEqual(state(daysFromNow: 4)?.shouldPrioritise, false)
        XCTAssertEqual(state(daysFromNow: 30)?.shouldPrioritise, false)
    }

    func test_urgency_ordersLeastToMostUrgent() {
        // The kitchen screen's priority sort relies on this ordering.
        XCTAssertLessThan(ExpiryUrgency.none.rawValue, ExpiryUrgency.thisWeek.rawValue)
        XCTAssertLessThan(ExpiryUrgency.thisWeek.rawValue, ExpiryUrgency.soon.rawValue)
        XCTAssertLessThan(ExpiryUrgency.soon.rawValue, ExpiryUrgency.tomorrow.rawValue)
        XCTAssertLessThan(ExpiryUrgency.tomorrow.rawValue, ExpiryUrgency.today.rawValue)
        XCTAssertLessThan(ExpiryUrgency.today.rawValue, ExpiryUrgency.expired.rawValue)
    }
}
