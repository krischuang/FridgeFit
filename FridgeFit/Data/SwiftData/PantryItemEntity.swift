//
//  PantryItemEntity.swift
//  FridgeFit
//

import Foundation
import SwiftData

/// How a `PantryItem` is stored on the device.
///
/// ## Why this is not `PantryItem`
///
/// `PantryItem` is a plain `struct` that imports only `Foundation`, and that
/// is load-bearing: every use case, view model and view in the app depends on
/// it, and none of them should gain a dependency on SwiftData because the
/// pantry happens to be stored locally today. So the domain keeps its struct,
/// this type is the storage shape, and `PantryItemMapper` converts between
/// them. The same separation `FirestorePantryRepository` already maintains
/// with its dictionaries.
///
/// ## Why the enums are stored as raw strings
///
/// `ingredientCategory`, `unit`, `storageLocation`, `openedState` and
/// `packageUnit` are `String` rather than their enum types. SwiftData can
/// persist `RawRepresentable` enums, but raw strings keep the stored shape
/// identical to the Firestore documents - which write `category.rawValue` and
/// `unit.rawValue` - so the two backends agree on what a stored pantry item
/// looks like, and an unrecognised value read back from a newer build decodes
/// to `nil` rather than refusing to load the row. Losing a storage-location
/// label is recoverable; losing the user's food is not.
///
/// ## What is deliberately not stored
///
/// `inventoryQuantity`, `storage`, `opened`, `isLowStock` and `expiryState`
/// are all computed on `PantryItem`. They stay computed. Storing them would
/// create a second amount that could drift from `quantity`/`unit`, which is
/// exactly what `PantryItem` is written to prevent.
@Model
final class PantryItemEntity {
    /// The domain `PantryItem.id`, unchanged.
    ///
    /// Unique at the storage level so re-adding the same item is a conflict
    /// rather than a duplicate row, and so an import could be re-run without
    /// doubling the pantry.
    @Attribute(.unique) var id: UUID

    /// The Firebase uid this item belongs to.
    ///
    /// A local database has no equivalent of Firestore's `users/{uid}` path,
    /// so the scoping that security rules provide in the cloud has to be a
    /// column here and a clause in every query. Without it, two accounts
    /// signing into the same device would share one pantry - see
    /// `SwiftDataPantryRepository`.
    var ownerID: String

    var ingredientName: String
    var ingredientCategory: String
    var quantity: Double
    var unit: String

    /// `nil` means expiry is not tracked, which is a different fact from
    /// "expires today" and is never defaulted to a date.
    var expiryDate: Date?
    var storageLocation: String?
    var openedState: String?
    var lowStockThreshold: Double?
    var packageUnit: String?
    var packageLevel: Double?

    /// This item's history.
    ///
    /// ## Why `.nullify` and not `.cascade`
    ///
    /// Cascade would be a bug, not a preference. `RecordFoodOutcomeUseCase`
    /// removes the pantry item and *then* writes the `finished` or
    /// `discarded` event describing what happened to it. Under a cascade
    /// rule, finishing a carton of milk would delete the item and take the
    /// event recording that it was finished with it - the activity history
    /// would be permanently empty for exactly the actions users most want to
    /// see.
    ///
    /// So the relationship goes `nil` and the event survives. The event also
    /// keeps `pantryItemID` as a plain `UUID` and a denormalised `itemName`,
    /// because after a nullify those are the only things left pointing at
    /// what happened.
    @Relationship(deleteRule: .nullify, inverse: \InventoryEventEntity.item)
    var events: [InventoryEventEntity] = []

    init(
        id: UUID,
        ownerID: String,
        ingredientName: String,
        ingredientCategory: String,
        quantity: Double,
        unit: String,
        expiryDate: Date? = nil,
        storageLocation: String? = nil,
        openedState: String? = nil,
        lowStockThreshold: Double? = nil,
        packageUnit: String? = nil,
        packageLevel: Double? = nil
    ) {
        self.id = id
        self.ownerID = ownerID
        self.ingredientName = ingredientName
        self.ingredientCategory = ingredientCategory
        self.quantity = quantity
        self.unit = unit
        self.expiryDate = expiryDate
        self.storageLocation = storageLocation
        self.openedState = openedState
        self.lowStockThreshold = lowStockThreshold
        self.packageUnit = packageUnit
        self.packageLevel = packageLevel
    }
}
