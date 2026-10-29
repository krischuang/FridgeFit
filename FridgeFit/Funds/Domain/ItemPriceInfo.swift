//
//  ItemPriceInfo.swift
//  FridgeFit
//

import Foundation

// FridgeFit's pantry only knows name/quantity/unit, so the money side (what you paid,
// when it goes off) is kept here instead, keyed by the pantry item's id. that way
// FridgeFunds still never writes to the pantry itself.
nonisolated struct ItemPriceInfo: Hashable, Codable, Sendable {
    let pantryItemID: PantryItemID
    // Cost per one unit of the item, in whatever unit the pantry uses for it.
    let unitCost: Money?
    let expiryDate: Date?

    init(pantryItemID: PantryItemID, unitCost: Money? = nil, expiryDate: Date? = nil) {
        self.pantryItemID = pantryItemID
        self.unitCost = unitCost
        self.expiryDate = expiryDate
    }
}
