//
//  InventoryEventRepository.swift
//  FridgeFit
//

import Foundation

/// Where the kitchen's activity history is stored.
///
/// Deliberately separate from `PantryRepository` rather than bolted onto it:
/// the pantry is current state and events are an append-only log, they have
/// different lifetimes (an event outlives the item it describes), and every
/// existing caller of `PantryRepository` would otherwise have to care about
/// a collection it never reads.
nonisolated protocol InventoryEventRepository: AnyObject {
    /// Most recent first.
    func fetchAll(limit: Int) async throws -> [InventoryEvent]

    /// Appends one event. Append-only - there is no update or edit, because
    /// history that can be rewritten isn't history.
    func append(_ event: InventoryEvent) async throws

    /// Deletes events by id, used only to undo an action the user has just
    /// taken. See `InventoryStore.undoLastAction()`.
    func remove(ids: [UUID]) async throws
}
