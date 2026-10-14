import Foundation

public enum ExpiryUrgency: Int, Codable, Sendable {
    case none
    case thisWeek
    case soon
    case tomorrow
    case today
    case expired
}

public struct ExpiryState: Equatable, Sendable {
    public var title: String
    public var urgency: ExpiryUrgency
    public var daysUntilExpiry: Int?

    public var shouldPrioritise: Bool {
        switch urgency {
        case .expired, .today, .tomorrow, .soon:
            return true
        case .thisWeek, .none:
            return false
        }
    }
}

public enum ExpiryService {
    public static func state(for date: Date?, now: Date = .now, calendar: Calendar = .current) -> ExpiryState? {
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
