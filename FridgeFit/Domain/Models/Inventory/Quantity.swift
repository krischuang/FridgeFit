//
//  Quantity.swift
//  FridgeFit
//

import Foundation

/// How precise a quantity record is.
///
/// Exact quantities support numeric rules ("you can't use more than you
/// have"). Approximate package levels let someone say "half a bottle"
/// without pretending the bottle was weighed.
nonisolated enum QuantityPrecision: String, Codable, Sendable {
    case exact
    case approximate
}

/// The tracking style used for a pantry quantity.
///
/// Countable and measurable food can be reduced by a recorded amount.
/// Packaged food carries an estimated level instead, because nobody weighs
/// a jar before putting it back in the fridge.
nonisolated enum QuantityType: String, Codable, CaseIterable, Identifiable, Sendable {
    case countable
    case measurable
    case packaged

    var id: String { rawValue }
}

/// Everyday package units a household tracks approximately.
nonisolated enum PackageUnit: String, Codable, CaseIterable, Identifiable, Sendable {
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

    var id: String { rawValue }
}

/// How much of a package is left.
nonisolated enum PackageLevel: Double, Codable, CaseIterable, Identifiable, Sendable {
    case full = 1
    case threeQuarters = 0.75
    case half = 0.5
    case quarter = 0.25
    case almostEmpty = 0.1

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .full: return "Full"
        case .threeQuarters: return "3/4"
        case .half: return "Half"
        case .quarter: return "1/4"
        case .almostEmpty: return "Almost empty"
        }
    }
}

/// How much of an ingredient is on hand.
///
/// ## Why this exists alongside `PantryItem.quantity`
///
/// `PantryItem` stores a flat `Double` plus a `MeasurementUnit`, and every
/// existing feature reads it that way - recipe feasibility, substitutions,
/// the receipt scanner. That contract is not changed here.
///
/// What this type adds is the *shape* of the amount: six eggs is a count,
/// 500 g of chicken is a measure, and half a bottle of milk is a package at
/// a level. All three still reduce to one number and one unit for storage
/// (see `PantryItem.inventoryQuantity`), so the richer reading is additive
/// rather than a replacement.
///
/// ## Why there is no `presence` case
///
/// The branch this was ported from had a fourth case for staples - "plenty",
/// "some", "low" - with no number behind it. It is deliberately left out:
/// `PantryItem.quantity` is a `Double` that
/// `EvaluateRecipeFeasibilityUseCase` compares against recipe amounts, so a
/// presence-only item would have to be written as some invented number.
/// Writing `0` would tell every existing feature the user has none of it;
/// writing `1` would be a quantity nobody stated. Neither is acceptable, so
/// the case is absent until the pantry contract can represent "some, amount
/// unknown" honestly.
nonisolated enum Quantity: Codable, Equatable, Sendable {
    case count(Int, unit: MeasurementUnit = .pieces)
    case measure(Double, unit: MeasurementUnit)
    case package(count: Int, unit: PackageUnit, level: PackageLevel)

    var precision: QuantityPrecision {
        switch self {
        case .count, .measure: return .exact
        case .package: return .approximate
        }
    }

    var type: QuantityType {
        switch self {
        case .count: return .countable
        case .measure: return .measurable
        case .package: return .packaged
        }
    }

    var displayText: String {
        QuantityFormatter.string(from: self)
    }

    /// The single number this quantity reduces to, in `storageUnit`.
    ///
    /// Non-optional on purpose: every case here has a real amount behind it.
    /// A half-full bottle is 0.5 of a bottle, which is what the pantry
    /// stores and what recipe feasibility compares against.
    var normalizedAmount: Double {
        switch self {
        case .count(let value, _):
            return Double(value)
        case .measure(let value, _):
            return value
        case .package(let count, _, let level):
            return Double(count) * level.rawValue
        }
    }

    /// The `MeasurementUnit` this quantity is stored under.
    ///
    /// Packages store as `.pieces` because a "bottle" is not a measurement
    /// unit; the package unit and level are kept beside it on `PantryItem`
    /// so the original reading survives a round trip.
    var storageUnit: MeasurementUnit {
        switch self {
        case .count(_, let unit): return unit
        case .measure(_, let unit): return unit
        case .package: return .pieces
        }
    }

    var isPositive: Bool {
        normalizedAmount > 0
    }

    /// The package kind and level, when this is a packaged quantity.
    ///
    /// Saves every caller writing the same `if case .package` to pull the two
    /// values out for storage.
    var packageReading: (unit: PackageUnit, level: PackageLevel)? {
        if case .package(_, let unit, let level) = self {
            return (unit, level)
        }
        return nil
    }

    /// The quantity left after a confirmed use.
    ///
    /// - The used amount must be greater than zero.
    /// - Use cannot exceed what is available.
    /// - The result can never be negative.
    func subtracting(_ amount: Double) throws -> Quantity {
        guard amount > 0 else {
            throw IngredientQuantityError.invalidAmount
        }

        switch self {
        case .count(let value, let unit):
            let used = Int(amount.rounded())
            guard used <= value else {
                throw IngredientQuantityError.amountExceedsAvailable(available: Double(value), unit: unit.symbol)
            }
            return .count(value - used, unit: unit)
        case .measure(let value, let unit):
            guard amount <= value else {
                throw IngredientQuantityError.amountExceedsAvailable(available: value, unit: unit.symbol)
            }
            return .measure(value - amount, unit: unit)
        case .package(let count, let unit, let level):
            let current = Double(count) * level.rawValue
            guard amount <= current else {
                throw IngredientQuantityError.amountExceedsAvailable(available: current, unit: unit.rawValue)
            }
            return .package(count: count, unit: unit, level: Self.nearestLevel(to: current - amount, count: count))
        }
    }

    /// A quantity adjusted by a correction rather than by recorded use.
    ///
    /// Corrections exist so fixing a typo isn't recorded as having eaten
    /// something - see `InventoryEventKind.quantityAdjusted`.
    func adjusted(by delta: Double) -> Quantity {
        switch self {
        case .count(let value, let unit):
            return .count(max(0, value + Int(delta.rounded())), unit: unit)
        case .measure(let value, let unit):
            return .measure(max(0, value + delta), unit: unit)
        case .package(let count, let unit, let level):
            let current = Double(count) * level.rawValue
            let next = max(0, min(Double(count), current + delta))
            return .package(count: max(1, count), unit: unit, level: Self.nearestLevel(to: next, count: count))
        }
    }

    /// The `PackageLevel` closest to `amount` spread over `count` packages.
    ///
    /// Package levels are a fixed ladder, so any arithmetic on them has to
    /// land back on a rung. Pulled out because `subtracting` and `adjusted`
    /// were doing the same search with slightly different code.
    private static func nearestLevel(to amount: Double, count: Int) -> PackageLevel {
        let ratio = count == 0 ? 0 : amount / Double(count)
        return PackageLevel.allCases.min {
            abs($0.rawValue - ratio) < abs($1.rawValue - ratio)
        } ?? .almostEmpty
    }
}

/// Why a quantity update was refused. Messages are written for the user.
nonisolated enum IngredientQuantityError: LocalizedError, Equatable {
    case invalidAmount
    case amountExceedsAvailable(available: Double, unit: String)

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "Enter an amount greater than zero before updating this food."
        case .amountExceedsAvailable(let available, let unit):
            return "Only \(QuantityFormatter.number(available)) \(unit) is available. Enter an amount up to \(QuantityFormatter.number(available)) \(unit)."
        }
    }
}

/// Formats quantities for display.
///
/// Separate from `MeasurementUnit.formatted(_:)` - which main already uses
/// for pantry rows - because package levels print as fractions ("½ bottle")
/// and a unit symbol alone can't express that.
nonisolated enum QuantityFormatter {
    static func string(from quantity: Quantity) -> String {
        switch quantity {
        case .count(let value, let unit):
            return "\(value) \(unit.symbol)"
        case .measure(let value, let unit):
            return "\(number(value)) \(unit.symbol)"
        case .package(let count, let unit, let level):
            let value = Double(count) * level.rawValue
            return "\(fractionOrNumber(value)) \(unit.rawValue)\(value > 1 ? "s" : "")"
        }
    }

    static func number(_ value: Double) -> String {
        let isWhole = value.rounded() == value
        return isWhole ? String(Int(value)) : String(format: "%.2f", value).trimmingTrailingFractionZeros()
    }

    private static func fractionOrNumber(_ value: Double) -> String {
        switch value {
        case 0.25: return "¼"
        case 0.5: return "½"
        case 0.75: return "¾"
        default: return number(value)
        }
    }
}

private extension String {
    nonisolated func trimmingTrailingFractionZeros() -> String {
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
