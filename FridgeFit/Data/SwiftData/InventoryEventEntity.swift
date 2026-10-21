//
//  InventoryEventEntity.swift
//  FridgeFit
//

import Foundation
import SwiftData

/// How one `InventoryEvent` is stored on the device.
///
/// Append-only, like the protocol it serves: there is no update path, because
/// `InventoryEventRepository` deliberately offers none - history that can be
/// rewritten isn't history. The only deletion is undo.
@Model
final class InventoryEventEntity {
    @Attribute(.unique) var id: UUID

    /// The Firebase uid this event belongs to. Same reasoning as
    /// `PantryItemEntity.ownerID`.
    var ownerID: String

    /// The `PantryItem.id` this happened to, kept as a plain value.
    ///
    /// Deliberately stored *beside* the `item` relationship rather than
    /// derived from it. The relationship is nullified when the item is
    /// deleted (see `PantryItemEntity.events`), and after that this is the
    /// only thing left identifying what the event was about -
    /// `InventoryStore.history(for:)` filters on exactly this value.
    var pantryItemID: UUID

    /// Denormalised on purpose: the item may be gone by the time this is
    /// read, and "Finished" with no name is not history.
    var itemName: String

    var kind: String

    /// An absent note and a stored empty string are different facts, and the
    /// activity list distinguishes them - so this stays optional.
    var note: String?

    /// Client clock, matching `FirestoreInventoryEventRepository`, which
    /// documents why a server timestamp is wrong here: the activity list is
    /// ordered by this and shows it, so a pending write reading back as `nil`
    /// would appear out of order.
    var date: Date

    /// The item this event describes, or `nil` once that item is gone.
    ///
    /// Optional because the event outlives the item. This is the inverse of
    /// `PantryItemEntity.events`.
    var item: PantryItemEntity?

    init(
        id: UUID,
        ownerID: String,
        pantryItemID: UUID,
        itemName: String,
        kind: String,
        note: String? = nil,
        date: Date,
        item: PantryItemEntity? = nil
    ) {
        self.id = id
        self.ownerID = ownerID
        self.pantryItemID = pantryItemID
        self.itemName = itemName
        self.kind = kind
        self.note = note
        self.date = date
        self.item = item
    }
}
