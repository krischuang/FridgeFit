import Foundation

/// One week of the recovery trend.
///
/// `percent` is deliberately optional. A week in which nothing was finished
/// and nothing was discarded has **no** recovery rate - the denominator is
/// zero - and drawing it as 0% would read as "you wasted everything" when in
/// fact you recorded nothing at all.
nonisolated struct WeeklyRecoveryPoint: Equatable, Sendable, Identifiable {
    let weekStart: Date
    /// `W1`…`W4`, oldest first, matching the chart's axis.
    let label: String
    /// Share of recorded outcomes that were finished rather than discarded,
    /// 0…100. `nil` when no outcome was recorded that week.
    let percent: Double?
    let finished: Int
    let discarded: Int

    var id: Date { weekStart }
}

/// An ingredient the household actually finished, and how often.
nonisolated struct FinishedStaple: Equatable, Sendable, Identifiable {
    /// The spelling from the most recent event, for display.
    let name: String
    /// How many `finished` events named it in the period.
    let timesFinished: Int

    var id: String { name.lowercased() }
}

/// What FridgeFit's own activity log can honestly say about the kitchen.
///
/// ## What is derived, and from what
///
/// `InventoryEvent` records that an item was *finished* (eaten) or
/// *discarded* (binned), with a name and a date. That is enough to answer
/// "of the food that left your kitchen, how much did you eat?" - which is
/// what `pantryEfficiencyPercent`, `weeklyRecovery` and
/// `zeroWasteStreakWeeks` report, each with an explicit denominator and an
/// explicit missing-data case.
///
/// ## What is still not derivable
///
/// An event does **not** retain the item's expiry date, price, or emissions
/// factors. So this type cannot claim an item was *rescued in time* (that
/// needs expiry-at-use), cannot put a dollar figure on anything (that needs
/// price - see `FundsEnvironment`, which owns the money side), and cannot
/// state CO₂e. Those stay `nil` rather than being estimated.
nonisolated struct KitchenImpactSummary: Equatable, Sendable {
    let monthStart: Date
    let finishedThisMonth: Int
    let discardedThisMonth: Int
    /// Share of this month's recorded outcomes that were finished rather
    /// than discarded, 0…100. `nil` when nothing left the kitchen this
    /// month, because the denominator would be zero.
    let pantryEfficiencyPercent: Double?
    /// The last four calendar weeks, oldest first, including the current
    /// (possibly partial) one.
    let weeklyRecovery: [WeeklyRecoveryPoint]
    /// Consecutive calendar weeks up to and including this one with no
    /// discard recorded, counted back no further than the week of the first
    /// recorded outcome. `nil` when no outcome has ever been recorded.
    let zeroWasteStreakWeeks: Int?
    /// Ingredients finished most often this month, commonest first.
    let mostFinishedStaples: [FinishedStaple]

    /// Items used up *before they expired*. Not derivable: an event does not
    /// keep the expiry date the item had when it was finished, so finishing
    /// a loaf cannot be distinguished from finishing it a day late.
    var rescuedItems: Int? { nil }
    /// Money saved. Not derivable from events: they carry no price. The
    /// money side of the Impact screen reads `FundsEnvironment` instead.
    var grocerySavings: Decimal? { nil }
    /// Emissions prevented. Not derivable: FridgeFit records no per-food
    /// emissions factors, and inventing one per ingredient would be a guess
    /// presented as a measurement.
    var preventedCO2eKilograms: Double? { nil }

    /// How many ingredients are listed under "most finished".
    static let stapleLimit = 3
    /// How many weeks the recovery chart covers.
    static let recoveryWeekCount = 4

    static func calculate(
        events: [InventoryEvent],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> KitchenImpactSummary {
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let thisMonth = events.filter { $0.date >= start && $0.date <= now }
        let finished = thisMonth.filter { $0.kind == .finished }
        let discarded = thisMonth.filter { $0.kind == .discarded }

        return KitchenImpactSummary(
            monthStart: start,
            finishedThisMonth: finished.count,
            discardedThisMonth: discarded.count,
            pantryEfficiencyPercent: recoveryPercent(finished: finished.count, discarded: discarded.count),
            weeklyRecovery: weeklyRecovery(events: events, now: now, calendar: calendar),
            zeroWasteStreakWeeks: zeroWasteStreak(events: events, now: now, calendar: calendar),
            mostFinishedStaples: staples(finishedEvents: finished)
        )
    }

    // MARK: - Derivations

    /// `finished / (finished + discarded)`, as a percentage. `nil` when the
    /// denominator is zero - the one case the caller must render differently.
    private static func recoveryPercent(finished: Int, discarded: Int) -> Double? {
        let total = finished + discarded
        guard total > 0 else { return nil }
        return Double(finished) / Double(total) * 100
    }

    private static func weeklyRecovery(
        events: [InventoryEvent],
        now: Date,
        calendar: Calendar
    ) -> [WeeklyRecoveryPoint] {
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }

        let weekStarts: [Date] = (0..<recoveryWeekCount).reversed().compactMap { weeksBack in
            calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: currentWeek.start)
        }

        return weekStarts.enumerated().map { index, weekStart in
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart
            let inWeek = events.filter { $0.date >= weekStart && $0.date < weekEnd }
            let finished = inWeek.filter { $0.kind == .finished }.count
            let discarded = inWeek.filter { $0.kind == .discarded }.count
            return WeeklyRecoveryPoint(
                weekStart: weekStart,
                label: "W\(index + 1)",
                percent: recoveryPercent(finished: finished, discarded: discarded),
                finished: finished,
                discarded: discarded
            )
        }
    }

    /// Counts back from this week while no discard was recorded.
    ///
    /// Bounded by the week of the earliest outcome event, so a brand new
    /// account does not get credited with a streak stretching into weeks it
    /// was not being used.
    private static func zeroWasteStreak(
        events: [InventoryEvent],
        now: Date,
        calendar: Calendar
    ) -> Int? {
        let outcomes = events.filter { $0.kind == .finished || $0.kind == .discarded }
        guard
            let earliest = outcomes.map(\.date).min(),
            let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now),
            let firstWeek = calendar.dateInterval(of: .weekOfYear, for: earliest)
        else { return nil }

        let weeksAvailable = (calendar.dateComponents(
            [.weekOfYear],
            from: firstWeek.start,
            to: currentWeek.start
        ).weekOfYear ?? 0) + 1

        let discardDates = outcomes.filter { $0.kind == .discarded }.map(\.date)

        var streak = 0
        for weeksBack in 0..<max(weeksAvailable, 1) {
            guard
                let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: currentWeek.start),
                let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart)
            else { break }
            let discardedThatWeek = discardDates.contains { $0 >= weekStart && $0 < weekEnd }
            if discardedThatWeek { break }
            streak += 1
        }
        return streak
    }

    private static func staples(finishedEvents: [InventoryEvent]) -> [FinishedStaple] {
        var counts: [String: Int] = [:]
        var displayName: [String: (name: String, date: Date)] = [:]

        for event in finishedEvents {
            let trimmed = event.itemName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            counts[key, default: 0] += 1
            if let existing = displayName[key], existing.date >= event.date { continue }
            displayName[key] = (trimmed, event.date)
        }

        return counts
            .map { FinishedStaple(name: displayName[$0.key]?.name ?? $0.key, timesFinished: $0.value) }
            .sorted { lhs, rhs in
                if lhs.timesFinished != rhs.timesFinished { return lhs.timesFinished > rhs.timesFinished }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(stapleLimit)
            .map { $0 }
    }
}
