//
//  CostBasis.swift
//  FridgeFit
//

import Foundation

// The recorded cost of one pantry item, used to value it and any waste from it.
struct CostBasis: Hashable, Codable, Sendable {
    let pantryItemID: PantryItemID
    // Cost per single unit of the item, e.g. per 100 g, per egg, per bottle.
    let unitCost: Money
    // The unit the cost is expressed against, kept consistent with inventory.
    let unit: String
    let recordedOn: Date

    init(pantryItemID: PantryItemID, unitCost: Money, unit: String, recordedOn: Date = Date()) {
        self.pantryItemID = pantryItemID
        self.unitCost = unitCost
        self.unit = unit
        self.recordedOn = recordedOn
    }
}
