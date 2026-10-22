//
//  PantryItemSnapshot.swift
//  FridgeFit
//

import Foundation

// A read-only snapshot of one pantry item, as reported by the Smart Fridge module.
nonisolated struct PantryItemSnapshot: Identifiable, Hashable, Codable, Sendable {
    let id: PantryItemID
    let name: String
    let quantity: Double
    let unit: String
    // The date the item expires, if known.
    let expiryDate: Date?
    // The recorded cost per unit, if this item has one.
    let unitCost: Money?
    // What kind of food this is, carried through from the pantry so screens
    // can draw the same glyph My Fridge draws. Defaults to `.other` for
    // snapshots built without one (test fixtures, previews).
    let category: IngredientCategory

    init(id: PantryItemID,
         name: String,
         quantity: Double,
         unit: String,
         expiryDate: Date? = nil,
         unitCost: Money? = nil,
         category: IngredientCategory = .other) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.expiryDate = expiryDate
        self.unitCost = unitCost
        self.category = category
    }

    // The total value of the quantity on hand, or `nil` if the item has no
    // recorded cost.
    var lineValue: Money? {
        guard let unitCost else { return nil }
        return unitCost.scaled(by: Decimal(quantity))
    }

    // Whole days until this item expires, measured from `reference`. Negative if
    // already expired, `nil` if there's no expiry date at all.
    func daysUntilExpiry(from reference: Date = Date()) -> Int? {
        guard let expiryDate else { return nil }
        let start = Calendar.current.startOfDay(for: reference)
        let end = Calendar.current.startOfDay(for: expiryDate)
        return Calendar.current.dateComponents([.day], from: start, to: end).day
    }
}
