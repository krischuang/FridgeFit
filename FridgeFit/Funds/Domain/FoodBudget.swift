import Foundation

/// How often a food budget resets.
enum BudgetCadence: String, Codable, CaseIterable, Sendable {
    case weekly
    case fortnightly

    /// The number of days in one period of this cadence.
    var lengthInDays: Int {
        switch self {
        case .weekly: return 7
        case .fortnightly: return 14
        }
    }

    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .fortnightly: return "Fortnightly"
        }
    }
}

/// A user's food-spending limit for one budget period. The limit must be greater
/// than zero, and only one budget is active at a time — its window runs from
/// `startDate` for `cadence.lengthInDays` days.
struct FoodBudget: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let limit: Money
    let cadence: BudgetCadence
    let startDate: Date

    init(id: UUID = UUID(), limit: Money, cadence: BudgetCadence, startDate: Date) {
        self.id = id
        self.limit = limit
        self.cadence = cadence
        self.startDate = startDate
    }

    /// The currency this budget is tracked in.
    var currency: Currency { limit.currency }

    /// The day the current period ends (exclusive).
    var endDate: Date {
        Calendar.current.date(byAdding: .day, value: cadence.lengthInDays, to: startDate) ?? startDate
    }

    /// The evenly-split amount available per day across the whole period.
    var dailyAllowance: Money {
        limit.dividedEvenly(by: cadence.lengthInDays)
    }

    /// Whether the given date falls inside this budget period.
    func contains(_ date: Date) -> Bool {
        date >= startDate && date < endDate
    }
}
