//
//  GrocerySpend.swift
//  FridgeFit
//

import Foundation

// A single grocery purchase logged against the active budget.
nonisolated struct GrocerySpend: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let amount: Money
    let spentOn: Date
    // Where it was bought, e.g. `"Woolworths"`, if the user recorded it.
    let store: String?
    // Pantry items this purchase added, if the user linked them.
    let purchasedItemIDs: [PantryItemID]
    let note: String?

    init(id: UUID = UUID(),
         amount: Money,
         spentOn: Date,
         store: String? = nil,
         purchasedItemIDs: [PantryItemID] = [],
         note: String? = nil) {
        self.id = id
        self.amount = amount
        self.spentOn = spentOn
        self.store = store
        self.purchasedItemIDs = purchasedItemIDs
        self.note = note
    }
}
