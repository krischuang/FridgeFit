import Foundation

// shared date formatter for the history screen rows
enum DateFormatting {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func string(_ date: Date) -> String {
        formatter.string(from: date)
    }
}
