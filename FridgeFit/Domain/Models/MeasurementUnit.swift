//
//  MeasurementUnit.swift
//  FridgeFit
//

import Foundation

/// The unit a pantry quantity is measured in. A fixed set (not free text)
/// so comparisons stay exact - no unit conversion.
enum MeasurementUnit: String, Codable, CaseIterable, Identifiable {
    case grams = "g"
    case kilograms = "kg"
    case milliliters = "ml"
    case liters = "L"
    case pieces = "pcs"
    case cups = "cup"
    case tablespoons = "tbsp"
    case teaspoons = "tsp"

    var id: String { rawValue }
    var symbol: String { rawValue }

    /// Formats a quantity for display, e.g. `500` -> `"500 g"`.
    func formatted(_ quantity: Double) -> String {
        let isWholeNumber = quantity.truncatingRemainder(dividingBy: 1) == 0
        let value = isWholeNumber
            ? String(format: "%.0f", quantity)
            : String(format: "%.1f", quantity)
        return "\(value) \(symbol)"
    }
}
