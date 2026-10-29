//
//  FundsEntities.swift
//  FridgeFit
//

import Foundation
import SwiftData

/// How FridgeFunds data is stored on the device.
///
/// ## Why money is a `String`
///
/// Every amount is persisted as its decimal *text*, not a `Double` and not a
/// `Decimal` attribute. The project already made this decision for Firestore
/// ("money is stored as a string on purpose - Decimal through a Double would
/// turn 4.5 into 4.4999999... eventually"), and the same reasoning applies
/// harder here, because this is the store the shipping build uses. A budget
/// of 320.00 that reads back as 319.99999999999997 is a defect the user can
/// see, and once it is in the database it is permanent.
///
/// Storing the text also keeps the two backends byte-comparable: a
/// `FoodBudget` round-tripped through SwiftData and the same budget
/// round-tripped through Firestore produce identical `Decimal`s, which is
/// what lets `FundsDecimal` be the single parsing rule for both.
///
/// ## Why `ownerID` is on every row
///
/// Same reason as `PantryItemEntity.ownerID`: a local database has no
/// `users/{uid}` path, so account scoping is a column and a clause in every
/// query. Without it two accounts on one device would share one budget.
///
/// ## Why these are new tables rather than changes to existing ones
///
/// Adding model types is a SwiftData lightweight migration - new tables, no
/// rewrite of existing rows, nothing to lose. An existing on-device pantry
/// opens unchanged after this schema grows; see
/// `SwiftDataPersistenceRetentionTests`.

/// The user's active food budget. One row per owner.
@Model
final class FoodBudgetEntity {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    /// Decimal text, e.g. `"320"` or `"120.50"`. See the note above.
    var limitAmount: String
    var currency: String
    var cadence: String
    var startDate: Date

    init(
        id: UUID,
        ownerID: String,
        limitAmount: String,
        currency: String,
        cadence: String,
        startDate: Date
    ) {
        self.id = id
        self.ownerID = ownerID
        self.limitAmount = limitAmount
        self.currency = currency
        self.cadence = cadence
        self.startDate = startDate
    }
}

/// One logged grocery purchase.
@Model
final class GrocerySpendEntity {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var amount: String
    var currency: String
    var spentOn: Date
    var store: String?
    var note: String?
    /// `PantryItemID.rawValue`s, kept as plain strings - these reference
    /// pantry items that may since have been used up, exactly as
    /// `InventoryEventEntity.pantryItemID` does.
    var purchasedItemIDs: [String]

    init(
        id: UUID,
        ownerID: String,
        amount: String,
        currency: String,
        spentOn: Date,
        store: String? = nil,
        note: String? = nil,
        purchasedItemIDs: [String] = []
    ) {
        self.id = id
        self.ownerID = ownerID
        self.amount = amount
        self.currency = currency
        self.spentOn = spentOn
        self.store = store
        self.note = note
        self.purchasedItemIDs = purchasedItemIDs
    }
}

/// One valued food-waste event.
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

    init(
        id: UUID,
        ownerID: String,
        pantryItemID: String,
        quantityDiscarded: Double,
        lostAmount: String,
        currency: String,
        discardedOn: Date,
        reason: String
    ) {
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

/// The price and expiry attached to one pantry item.
///
/// Identity is `(ownerID, pantryItemID)`, enforced by
/// `SwiftDataItemPriceStore` rather than by `@Attribute(.unique)` - the same
/// choice `SavedRecipeEntity` documents, and for the same reason: two
/// accounts on one device can each price their own copy of an item.
@Model
final class ItemPriceEntity {
    var ownerID: String
    var pantryItemID: String
    /// `nil` when a price was never recorded but an expiry was.
    var unitCost: String?
    var currency: String?
    var expiryDate: Date?

    init(
        ownerID: String,
        pantryItemID: String,
        unitCost: String? = nil,
        currency: String? = nil,
        expiryDate: Date? = nil
    ) {
        self.ownerID = ownerID
        self.pantryItemID = pantryItemID
        self.unitCost = unitCost
        self.currency = currency
        self.expiryDate = expiryDate
    }
}

/// The last price paid for an ingredient *by name*, kept after the item is
/// gone, so re-buying milk does not mean re-typing its price.
///
/// Identity is `(ownerID, key)`, where `key` is
/// `PriceBookEntry.key(for: name)`.
@Model
final class PriceBookEntryEntity {
    var ownerID: String
    var key: String
    var displayName: String
    var unitCost: String
    var currency: String
    var unit: String
    var recordedOn: Date

    init(
        ownerID: String,
        key: String,
        displayName: String,
        unitCost: String,
        currency: String,
        unit: String,
        recordedOn: Date
    ) {
        self.ownerID = ownerID
        self.key = key
        self.displayName = displayName
        self.unitCost = unitCost
        self.currency = currency
        self.unit = unit
        self.recordedOn = recordedOn
    }
}

/// The one rule for turning a `Decimal` into stored text and back.
///
/// Shared by the SwiftData stores and worth being a single function: the
/// write side must not use the current locale (a device set to German would
/// store `"4,50"`, which the read side would then fail to parse and silently
/// drop the price), and the read side must accept exactly what the write
/// side produces. POSIX on both, always.
nonisolated enum FundsDecimal {
    static func text(_ value: Decimal) -> String {
        "\(value)"
    }

    static func value(_ text: String?) -> Decimal? {
        guard let text else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func money(_ amount: String?, _ currency: String?) -> Money? {
        guard
            let value = value(amount),
            let currency = currency.flatMap(Currency.init(rawValue:))
        else { return nil }
        return Money(value, currency)
    }
}
