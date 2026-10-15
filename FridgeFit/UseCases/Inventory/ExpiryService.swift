//
//  ExpiryService.swift
//  FridgeFit
//

import Foundation

/// How urgent an approaching expiry date is.
///
/// Ordered least to most urgent so the kitchen screen can compare two items
/// without a lookup table.
nonisolated enum ExpiryUrgency: Int, Codable, Sendable {
    case none
    case thisWeek
    case soon
    case tomorrow
    case today
    case expired
}

/// An expiry date, read as something the UI can show.
///
/// `daysUntilExpiry` is negative for food that has already gone off, which
/// is what lets the "Use First" list sort the worst offender to the top.
nonisolated struct ExpiryState: Equatable, Sendable {
    var title: String
    var urgency: ExpiryUrgency
    var daysUntilExpiry: Int?

    /// Whether this belongs in "Use First".
    ///
    /// Four to seven days out is deliberately excluded: surfacing a week's
    /// worth of food as urgent makes the section meaningless.
    var shouldPrioritise: Bool {
        switch urgency {
        case .expired, .today, .tomorrow, .soon:
            return true
        case .thisWeek, .none:
            return false
        }
    }
}

/// Turns an expiry date into urgency.
///
/// Pure and injectable on `now`/`calendar` so the boundaries ("today" vs
/// "tomorrow") can be tested without waiting for midnight. Deliberately not
/// stored on `PantryItem`: urgency changes as time passes, so persisting it
/// would mean every item was wrong by the next morning.
nonisolated enum ExpiryService {
    static func state(for date: Date?, now: Date = .now, calendar: Calendar = .current) -> ExpiryState? {
        guard let date else { return nil }

        let startOfToday = calendar.startOfDay(for: now)
        let expiryDay = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startOfToday, to: expiryDay).day ?? 0

        switch days {
        case ..<0:
            return ExpiryState(title: "Expired", urgency: .expired, daysUntilExpiry: days)
        case 0:
            return ExpiryState(title: "Today", urgency: .today, daysUntilExpiry: days)
        case 1:
            return ExpiryState(title: "Tomorrow", urgency: .tomorrow, daysUntilExpiry: days)
        case 2...3:
            return ExpiryState(title: "\(days) days", urgency: .soon, daysUntilExpiry: days)
        case 4...7:
            return ExpiryState(title: "This week", urgency: .thisWeek, daysUntilExpiry: days)
        default:
            return ExpiryState(title: formatted(date: date), urgency: .none, daysUntilExpiry: days)
        }
    }

    private static func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }
}
