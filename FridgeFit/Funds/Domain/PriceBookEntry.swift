//
//  PriceBookEntry.swift
//  FridgeFit
//

import Foundation

// "last time you bought milk it was $2.25 per L". kept by ingredient name rather
// than pantry item id, so it's still around after the milk is used up - that's
// what lets a recipe guess what the missing stuff will cost to buy.
struct PriceBookEntry: Hashable, Codable, Sendable {
    // normalised name, see `key(for:)`
    let key: String
    // how the user wrote it, for showing
    let displayName: String
    // price for one `unit`
    let unitCost: Money
    // MeasurementUnit raw value ("g", "L", "pcs" ...), same as the pantry uses
    let unit: String
    let recordedOn: Date

    init(displayName: String, unitCost: Money, unit: String, recordedOn: Date = Date()) {
        self.key = Self.key(for: displayName)
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.unitCost = unitCost
        self.unit = unit
        self.recordedOn = recordedOn
    }

    // same matching rule the pantry uses (Ingredient.matches): trim + ignore case
    static func key(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
