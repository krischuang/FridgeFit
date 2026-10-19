//
//  FundsEntities.swift
//  FridgeFit
//

import Foundation
import SwiftData

// SwiftData rows for FridgeFunds. same rules as PantryItemEntity: every row has
// an ownerID (the signed-in uid) and nothing is shared between accounts.
// money amounts are stored as strings - Decimal through a Double drifts
// (4.5 -> 4.4999...), same reason the Firestore mapping does it.
// none of these point at PantryItemEntity: a price or a waste record outlives
// the pantry item it was about, so it just keeps the item's id as a string.

@Model
final class FundsBudgetEntity {
    var ownerID: String
    var budgetID: UUID
    var limitAmount: String
    var currency: String
    var cadence: String
    var startDate: Date

    init(ownerID: String, budgetID: UUID, limitAmount: String, currency: String, cadence: String, startDate: Date) {
        self.ownerID = ownerID
        self.budgetID = budgetID
        self.limitAmount = limitAmount
        self.currency = currency
        self.cadence = cadence
        self.startDate = startDate
    }
}

@Model
final class GrocerySpendEntity {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var amount: String
    var currency: String
    var spentOn: Date
    var store: String?
    var purchasedItemIDs: [String]
    var note: String?

    init(id: UUID, ownerID: String, amount: String, currency: String, spentOn: Date,
         store: String?, purchasedItemIDs: [String], note: String?) {
        self.id = id
        self.ownerID = ownerID
        self.amount = amount
        self.currency = currency
        self.spentOn = spentOn
        self.store = store
        self.purchasedItemIDs = purchasedItemIDs
        self.note = note
    }
}

@Model
final class WastedFoodCostEntity {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var pantryItemID: String
    var quantityDiscarded: Double
    var lostAmount: String
    var currency: String
    var discardedOn: Date
    var reason: String

    init(id: UUID, ownerID: String, pantryItemID: String, quantityDiscarded: Double,
         lostAmount: String, currency: String, discardedOn: Date, reason: String) {
        self.id = id
        self.ownerID = ownerID
        self.pantryItemID = pantryItemID
        self.quantityDiscarded = quantityDiscarded
        self.lostAmount = lostAmount
        self.currency = currency
        self.discardedOn = discardedOn
        self.reason = reason
    }
}

@Model
final class ItemPriceEntity {
    var ownerID: String
    var pantryItemID: String
    var unitCost: String?
    var currency: String?
    // only for prices saved before the pantry had its own expiry field
    var expiryDate: Date?

    init(ownerID: String, pantryItemID: String, unitCost: String?, currency: String?, expiryDate: Date?) {
        self.ownerID = ownerID
        self.pantryItemID = pantryItemID
        self.unitCost = unitCost
        self.currency = currency
        self.expiryDate = expiryDate
    }
}

// entity <-> domain. plain functions so they can be tested on their own
enum FundsEntityMapper {
    static func string(_ money: Money) -> String { "\(money.amount)" }

    static func money(_ amount: String?, _ currency: String?) -> Money? {
        guard
            let amount,
            let value = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")),
            let currency = currency.flatMap(Currency.init(rawValue:))
        else { return nil }
        return Money(value, currency)
    }

    static func toDomain(_ e: FundsBudgetEntity) -> FoodBudget? {
        guard let limit = money(e.limitAmount, e.currency),
              let cadence = BudgetCadence(rawValue: e.cadence) else { return nil }
        return FoodBudget(id: e.budgetID, limit: limit, cadence: cadence, startDate: e.startDate)
    }

    static func toDomain(_ e: GrocerySpendEntity) -> GrocerySpend? {
        guard let amount = money(e.amount, e.currency) else { return nil }
        return GrocerySpend(id: e.id, amount: amount, spentOn: e.spentOn, store: e.store,
                            purchasedItemIDs: e.purchasedItemIDs.map(PantryItemID.init), note: e.note)
    }

    static func toDomain(_ e: WastedFoodCostEntity) -> WastedFoodCost? {
        guard let lost = money(e.lostAmount, e.currency),
              let reason = DiscardReason(rawValue: e.reason) else { return nil }
        return WastedFoodCost(id: e.id, pantryItemID: PantryItemID(e.pantryItemID),
                              quantityDiscarded: e.quantityDiscarded, lostAmount: lost,
                              discardedOn: e.discardedOn, reason: reason)
    }

    static func toDomain(_ e: ItemPriceEntity) -> ItemPriceInfo {
        ItemPriceInfo(pantryItemID: PantryItemID(e.pantryItemID),
                      unitCost: money(e.unitCost, e.currency),
                      expiryDate: e.expiryDate)
    }
}
