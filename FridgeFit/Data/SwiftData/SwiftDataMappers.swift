//
//  SwiftDataMappers.swift
//  FridgeFit
//

import Foundation

/// Entity ↔ domain conversion for the pantry.
///
/// Pure functions with no `ModelContext` and no container, so the whole field
/// mapping is unit testable without a database - the same approach
/// `FirestorePantryRepository`'s static `encode`/`decode` already takes, for
/// the same reason.
enum PantryItemMapper {

    /// Reads a stored row as a domain `PantryItem`.
    ///
    /// Unrecognised stored values fall back rather than failing the row:
    /// an unknown category reads as `.other`, an unknown unit as `.pieces`,
    /// and the optional kitchen fields as `nil`. A build that cannot name a
    /// storage location should still show the user their food - which is the
    /// rule `FirestorePantryRepository.decode` documents and follows.
    static func toDomain(_ entity: PantryItemEntity) -> PantryItem {
        PantryItem(
            id: entity.id,
            ingredient: Ingredient(
                name: entity.ingredientName,
                category: IngredientCategory(rawValue: entity.ingredientCategory) ?? .other
            ),
            quantity: entity.quantity,
            unit: MeasurementUnit(rawValue: entity.unit) ?? .pieces,
            expiryDate: entity.expiryDate,
            storageLocation: entity.storageLocation.flatMap(StorageLocation.init(rawValue:)),
            openedState: entity.openedState.flatMap(OpenedState.init(rawValue:)),
            lowStockThreshold: entity.lowStockThreshold,
            packageUnit: entity.packageUnit.flatMap(PackageUnit.init(rawValue:)),
            packageLevel: entity.packageLevel.flatMap(PackageLevel.init(rawValue:))
        )
    }

    /// Builds a new row. Used only by `add`.
    static func makeEntity(_ item: PantryItem, ownerID: String) -> PantryItemEntity {
        PantryItemEntity(
            id: item.id,
            ownerID: ownerID,
            ingredientName: item.ingredient.name,
            ingredientCategory: item.ingredient.category.rawValue,
            quantity: item.quantity,
            unit: item.unit.rawValue,
            expiryDate: item.expiryDate,
            storageLocation: item.storageLocation?.rawValue,
            openedState: item.openedState?.rawValue,
            lowStockThreshold: item.lowStockThreshold,
            packageUnit: item.packageUnit?.rawValue,
            packageLevel: item.packageLevel?.rawValue
        )
    }

    /// Writes `item` onto an existing row.
    ///
    /// Updates mutate the fetched object rather than inserting a replacement.
    /// Inserting a second entity with the same `id` would trip the unique
    /// constraint, and SwiftData's change tracking only sees edits made to
    /// objects it already manages.
    ///
    /// Every field is assigned, including the optional ones, so clearing an
    /// expiry date actually clears it. `FirestorePantryRepository` has to send
    /// `FieldValue.delete()` for the same reason - an omitted key there, and
    /// an unassigned property here, would silently keep a value the user just
    /// removed.
    static func apply(_ item: PantryItem, to entity: PantryItemEntity) {
        entity.ingredientName = item.ingredient.name
        entity.ingredientCategory = item.ingredient.category.rawValue
        entity.quantity = item.quantity
        entity.unit = item.unit.rawValue
        entity.expiryDate = item.expiryDate
        entity.storageLocation = item.storageLocation?.rawValue
        entity.openedState = item.openedState?.rawValue
        entity.lowStockThreshold = item.lowStockThreshold
        entity.packageUnit = item.packageUnit?.rawValue
        entity.packageLevel = item.packageLevel?.rawValue
    }
}

/// Entity ↔ domain conversion for the activity log.
enum InventoryEventMapper {

    /// An unrecognised `kind` is the one field with no safe fallback: an
    /// event whose meaning this build cannot read would be rendered as some
    /// other action, and "discarded" shown as "finished" is a false statement
    /// about the user's food. So it returns `nil` and the row is skipped,
    /// matching `FirestoreInventoryEventRepository.decode`.
    static func toDomain(_ entity: InventoryEventEntity) -> InventoryEvent? {
        guard let kind = InventoryEventKind(rawValue: entity.kind) else { return nil }
        return InventoryEvent(
            id: entity.id,
            pantryItemID: entity.pantryItemID,
            itemName: entity.itemName,
            kind: kind,
            note: entity.note,
            date: entity.date
        )
    }

    /// Builds a row. `item` links the event to the pantry item it describes,
    /// and is `nil` when that item has already been removed - which is the
    /// normal case for `finished` and `discarded`.
    static func makeEntity(
        _ event: InventoryEvent,
        ownerID: String,
        item: PantryItemEntity?
    ) -> InventoryEventEntity {
        InventoryEventEntity(
            id: event.id,
            ownerID: ownerID,
            pantryItemID: event.pantryItemID,
            itemName: event.itemName,
            kind: event.kind.rawValue,
            note: event.note,
            date: event.date,
            item: item
        )
    }
}
