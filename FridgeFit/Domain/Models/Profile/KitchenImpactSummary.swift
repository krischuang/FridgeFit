import Foundation

/// A conservative reading of inventory activity for the Impact & Waste UI.
///
/// FridgeFit currently records that an item was finished or discarded, but an
/// event does not retain the item's expiry date, price, or emissions factors.
/// Those missing inputs mean the app cannot honestly infer that an item was
/// rescued, calculate savings/CO2e, or build a recovery percentage trend.
nonisolated struct KitchenImpactSummary: Equatable, Sendable {
    let monthStart: Date
    let finishedThisMonth: Int
    let discardedThisMonth: Int

    var rescuedItems: Int? { nil }
    var grocerySavings: Decimal? { nil }
    var preventedCO2eKilograms: Double? { nil }
    var pantryEfficiencyPercent: Double? { nil }
    var zeroWasteStreakWeeks: Int? { nil }
    var frequentlyRescuedStaples: [String] { [] }
    var weeklyRecoveryPercentages: [Double] { [] }

    static func calculate(
        events: [InventoryEvent],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> KitchenImpactSummary {
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let thisMonth = events.filter { $0.date >= start && $0.date <= now }
        return KitchenImpactSummary(
            monthStart: start,
            finishedThisMonth: thisMonth.filter { $0.kind == .finished }.count,
            discardedThisMonth: thisMonth.filter { $0.kind == .discarded }.count
        )
    }
}
