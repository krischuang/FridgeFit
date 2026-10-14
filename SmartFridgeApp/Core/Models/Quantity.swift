import Foundation

/// Describes how precise a household quantity record is.
///
/// Exact quantities support numeric inventory rules. Approximate package levels
/// help users maintain useful stock awareness without pretending a package has
/// been weighed. Presence is used when exact measurement would create
/// unnecessary household admin.
public enum QuantityPrecision: String, Codable, Sendable {
    case exact
    case approximate
    case presence
}

/// Describes the household tracking style used for a food quantity.
///
/// Countable and measurable food can be reduced by recorded use. Packaged food
/// uses an estimated package level, while staples represent availability rather
/// than a precise amount.
public enum QuantityType: String, Codable, CaseIterable, Identifiable, Sendable {
    case countable
    case measurable
    case packaged
    case staple

    public var id: String { rawValue }
}

/// Represents exact count, weight, and volume units used by household inventory.
public enum MeasurementUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case pieces = "pcs"
    case grams = "g"
    case kilograms = "kg"
    case millilitres = "ml"
    case litres = "L"

    public var id: String { rawValue }
}

/// Represents everyday package units that households commonly track approximately.
public enum PackageUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case bottle
    case pack
    case tub
    case block
    case bag
    case box
    case jar
    case can
    case tray
    case bunch
    case slice
    case loaf
    case stick

    public var id: String { rawValue }
}

/// Represents the approximate remaining level of a package.
///
/// Package level supports quick household updates such as "half a bottle" when
/// exact measuring would be too much friction for normal kitchen use.
public enum PackageLevel: Double, Codable, CaseIterable, Identifiable, Sendable {
    case full = 1
    case threeQuarters = 0.75
    case half = 0.5
    case quarter = 0.25
    case almostEmpty = 0.1

    public var id: Double { rawValue }

    public var title: String {
        switch self {
        case .full: "Full"
        case .threeQuarters: "3/4"
        case .half: "Half"
        case .quarter: "1/4"
        case .almostEmpty: "Almost empty"
        }
    }
}

/// Represents non-numeric availability for household staples.
///
/// Presence quantities are used for foods where the useful question is whether
/// the household has enough, some, or a low amount rather than an exact count.
public enum PresenceLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case plenty
    case some
    case low
    case available

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .plenty: "Plenty"
        case .some: "Some"
        case .low: "Low"
        case .available: "Available"
        }
    }
}

/// Represents the remaining amount of food in household inventory.
///
/// Exact count and measured quantities protect numeric business rules such as
/// "used amount cannot exceed available amount." Package quantities are
/// deliberately approximate. Presence quantities represent staples where exact
/// measurement is not useful. Quantity operations must never create a negative
/// remaining amount.
public enum Quantity: Codable, Equatable, Sendable {
    case count(Int, unit: MeasurementUnit = .pieces)
    case measure(Double, unit: MeasurementUnit)
    case package(count: Int, unit: PackageUnit, level: PackageLevel)
    case presence(PresenceLevel)

    public var precision: QuantityPrecision {
        switch self {
        case .count, .measure: .exact
        case .package: .approximate
        case .presence: .presence
        }
    }

    public var type: QuantityType {
        switch self {
        case .count: .countable
        case .measure: .measurable
        case .package: .packaged
        case .presence: .staple
        }
    }

    public var displayText: String {
        QuantityFormatter.string(from: self)
    }

    public var normalizedAmount: Double? {
        switch self {
        case .count(let value, _):
            return Double(value)
        case .measure(let value, _):
            return value
        case .package(let count, _, let level):
            return Double(count) * level.rawValue
        case .presence:
            return nil
        }
    }

    public var isPositive: Bool {
        switch self {
        case .count(let value, _):
            return value > 0
        case .measure(let value, _):
            return value > 0
        case .package(let count, _, let level):
            return count > 0 && level.rawValue > 0
        case .presence:
            return true
        }
    }

    /// Returns the remaining quantity after a confirmed household use.
    ///
    /// Business Rules:
    /// - The used amount must be greater than zero.
    /// - Numeric usage cannot exceed the available quantity.
    /// - Presence quantities cannot accept numeric use because they do not
    ///   represent a measurable amount.
    public func subtracting(_ amount: Double) throws -> Quantity {
        guard amount > 0 else {
            throw IngredientQuantityError.invalidAmount
        }

        switch self {
        case .count(let value, let unit):
            let used = Int(amount.rounded())
            guard used <= value else {
                throw IngredientQuantityError.amountExceedsAvailable(available: Double(value), unit: unit.rawValue)
            }
            return .count(value - used, unit: unit)
        case .measure(let value, let unit):
            guard amount <= value else {
                throw IngredientQuantityError.amountExceedsAvailable(available: value, unit: unit.rawValue)
            }
            return .measure(value - amount, unit: unit)
        case .package(let count, let unit, let level):
            let current = Double(count) * level.rawValue
            guard amount <= current else {
                throw IngredientQuantityError.amountExceedsAvailable(available: current, unit: unit.rawValue)
            }
            let remaining = current - amount
            let ratio = count == 0 ? 0 : remaining / Double(count)
            let nextLevel = PackageLevel.allCases.min {
                abs($0.rawValue - ratio) < abs($1.rawValue - ratio)
            } ?? .almostEmpty
            return .package(count: count, unit: unit, level: nextLevel)
        case .presence:
            throw IngredientQuantityError.incompatibleUnit
        }
    }

    /// Returns a quantity adjusted by a correction rather than recorded consumption.
    ///
    /// Corrections support fixing inventory data while keeping semantic activity
    /// separate from a meaningful `used` event.
    public func adjusted(by delta: Double) -> Quantity {
        switch self {
        case .count(let value, let unit):
            return .count(max(0, value + Int(delta.rounded())), unit: unit)
        case .measure(let value, let unit):
            return .measure(max(0, value + delta), unit: unit)
        case .package(let count, let unit, let level):
            let next = max(0, min(Double(count), Double(count) * level.rawValue + delta))
            let levelValue = count == 0 ? 0 : next / Double(count)
            let nearest = PackageLevel.allCases.min { abs($0.rawValue - levelValue) < abs($1.rawValue - levelValue) } ?? .almostEmpty
            return .package(count: max(1, count), unit: unit, level: nearest)
        case .presence:
            return self
        }
    }

}

/// Represents domain failures when a household quantity cannot support an update.
///
/// These errors are phrased so the UI can tell the user what happened and how
/// to recover without exposing technical calculation details.
public enum IngredientQuantityError: LocalizedError, Equatable {
    case invalidAmount
    case amountExceedsAvailable(available: Double, unit: String)
    case incompatibleUnit

    public var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "Enter an amount greater than zero before updating this food."
        case .amountExceedsAvailable(let available, let unit):
            return "Only \(QuantityFormatter.number(available)) \(unit) is available. Enter an amount up to \(QuantityFormatter.number(available)) \(unit)."
        case .incompatibleUnit:
            return "This food does not have a measurable amount. Correct the quantity before recording use."
        }
    }
}

public enum QuantityFormatter {
    public static func string(from quantity: Quantity) -> String {
        switch quantity {
        case .count(let value, let unit):
            return "\(value) \(unit.rawValue)"
        case .measure(let value, let unit):
            return "\(number(value)) \(unit.rawValue)"
        case .package(let count, let unit, let level):
            let value = Double(count) * level.rawValue
            return "\(fractionOrNumber(value)) \(unit.rawValue)\(value > 1 ? "s" : "")"
        case .presence(let level):
            return level.title
        }
    }

    public static func number(_ value: Double) -> String {
        let isWhole = value.rounded() == value
        return isWhole ? String(Int(value)) : String(format: "%.2f", value).trimmingTrailingFractionZeros()
    }

    private static func fractionOrNumber(_ value: Double) -> String {
        switch value {
        case 0.25: "¼"
        case 0.5: "½"
        case 0.75: "¾"
        default: number(value)
        }
    }
}

private extension String {
    func trimmingTrailingFractionZeros() -> String {
        var output = self
        while output.contains(".") && output.last == "0" {
            output.removeLast()
        }
        if output.last == "." {
            output.removeLast()
        }
        return output
    }
}
