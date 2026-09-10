//
//  IngredientAvailability.swift
//  FridgeFit
//

import Foundation

/// Whether a recipe ingredient is covered by what's currently in the
/// pantry, based on comparing required quantity vs. on-hand quantity.
///
/// Four states instead of a `Bool` because "have some, not enough" is a
/// different situation from "have none". `quantityUnverified` is its own
/// state too, since claiming "available" when the units can't be safely
/// compared (e.g. grams vs. cups) would be guessing, not measuring - see
/// `MeasurementUnit.convert(quantity:from:to:)`.
enum IngredientAvailability: Equatable, Hashable {
    /// Pantry has at least the required quantity, once safely converted to
    /// the recipe's unit.
    case available
    /// In the pantry, safely comparable, just not enough of it.
    case insufficient
    /// Not in the pantry at all.
    case missing
    /// In the pantry, but in a unit that can't be safely converted to the
    /// recipe's unit, so the quantities can't be compared.
    case quantityUnverified

    var displayName: String {
        switch self {
        case .available: return "Available"
        case .insufficient: return "Insufficient quantity"
        case .missing: return "Missing"
        case .quantityUnverified: return "Check amount"
        }
    }

    var symbolName: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .insufficient: return "exclamationmark.triangle.fill"
        case .missing: return "xmark.circle.fill"
        case .quantityUnverified: return "questionmark.circle.fill"
        }
    }
}
