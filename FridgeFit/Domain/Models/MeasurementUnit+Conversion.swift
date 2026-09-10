//
//  MeasurementUnit+Conversion.swift
//  FridgeFit
//

import Foundation

extension MeasurementUnit {
    /// Converts `quantity` from `unit` into `targetUnit`, if that
    /// conversion is safe and unambiguous.
    ///
    /// Only exact, same-dimension conversions are supported - mass (g/kg)
    /// and volume (ml/L). Everything else (different dimensions like grams
    /// vs. milliliters, or units this phase doesn't model a ratio for,
    /// like cups/tbsp/tsp) returns `nil` rather than guessing, so callers
    /// can fail closed (see `IngredientAvailability.quantityUnverified`)
    /// instead of silently comparing incompatible amounts.
    static func convert(quantity: Double, from unit: MeasurementUnit, to targetUnit: MeasurementUnit) -> Double? {
        if unit == targetUnit {
            return quantity
        }
        switch (unit, targetUnit) {
        case (.grams, .kilograms):
            return quantity / 1000
        case (.kilograms, .grams):
            return quantity * 1000
        case (.milliliters, .liters):
            return quantity / 1000
        case (.liters, .milliliters):
            return quantity * 1000
        default:
            return nil
        }
    }
}
