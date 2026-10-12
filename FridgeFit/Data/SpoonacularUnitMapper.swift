//
//  SpoonacularUnitMapper.swift
//  FridgeFit
//

import Foundation

/// Maps Spoonacular's free-text unit strings onto `MeasurementUnit`.
///
/// Ported from LettuceDecide, where each rule below fixed a bug seen in live
/// data. Anything unrecognised returns `nil` - the caller keeps the raw text
/// for display instead of guessing a unit.
enum SpoonacularUnitMapper {
    struct Mapped: Equatable {
        let unit: MeasurementUnit?
        /// `true` for units like "servings" whose amount is not a real count.
        let quantityIsUncertain: Bool
    }

    static func map(_ raw: String) -> Mapped {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Capital "T" = tablespoon, lowercase "t" = teaspoon. The one
        // case-sensitive abbreviation in recipe notation, so it must be
        // checked before lowercasing.
        if trimmed == "T" { return Mapped(unit: .tablespoons, quantityIsUncertain: false) }
        if trimmed == "t" { return Mapped(unit: .teaspoons, quantityIsUncertain: false) }

        switch trimmed.lowercased() {
        case "g", "gram", "grams", "gr":
            return Mapped(unit: .grams, quantityIsUncertain: false)
        case "kg", "kilogram", "kilograms":
            return Mapped(unit: .kilograms, quantityIsUncertain: false)
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres":
            return Mapped(unit: .milliliters, quantityIsUncertain: false)
        case "l", "liter", "liters", "litre", "litres":
            return Mapped(unit: .liters, quantityIsUncertain: false)
        case "", "piece", "pieces", "x", "whole":
            return Mapped(unit: .pieces, quantityIsUncertain: false)
        case "serving", "servings":
            // Not a piece count - Spoonacular uses it for per-serving ratios.
            // Summing it as pieces produced "200 pcs of onion" in LettuceDecide.
            return Mapped(unit: .pieces, quantityIsUncertain: true)
        case "cup", "cups", "c":
            return Mapped(unit: .cups, quantityIsUncertain: false)
        case "tb", "tbs", "tbsp", "tbsps", "tablespoon", "tablespoons":
            return Mapped(unit: .tablespoons, quantityIsUncertain: false)
        case "tsp", "tsps", "teaspoon", "teaspoons":
            return Mapped(unit: .teaspoons, quantityIsUncertain: false)
        default:
            return Mapped(unit: nil, quantityIsUncertain: false)
        }
    }
}
