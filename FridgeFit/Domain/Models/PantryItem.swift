//
//  PantryItem.swift
//  FridgeFit
//

import Foundation

/// An `Ingredient` and how much of it the user currently has on hand.
struct PantryItem: Identifiable, Hashable, Codable {
    let id: UUID
    var ingredient: Ingredient
    var quantity: Double
    var unit: MeasurementUnit

    init(id: UUID = UUID(), ingredient: Ingredient, quantity: Double, unit: MeasurementUnit) {
        self.id = id
        self.ingredient = ingredient
        self.quantity = quantity
        self.unit = unit
    }

    var name: String { ingredient.name }

    var formattedQuantity: String { unit.formatted(quantity) }
}
