//
//  PantryRepository.swift
//  FridgeFit
//

import Foundation

/// Abstraction over where the pantry is stored. Use cases depend on this
/// protocol, not a concrete storage type, so swapping the in-memory test
/// double for `FirestorePantryRepository` doesn't require touching any use
/// case.
protocol PantryRepository: AnyObject {
    /// Every item currently in the caller's pantry.
    func fetchAll() async throws -> [PantryItem]

    /// Adds a new item. Caller is responsible for validating it first -
    /// see `AddPantryItemUseCase`.
    func add(_ item: PantryItem) async throws

    /// Replaces the item matching `item.id`.
    ///
    /// - Throws: `UpdatePantryItemError.itemNotFound` if no item with
    ///   `item.id` exists.
    func update(_ item: PantryItem) async throws

    /// Removes the item with the given `id`.
    ///
    /// - Throws: `RemovePantryItemError.pantryItemNotFound` if no item with
    ///   `id` exists.
    func remove(id: UUID) async throws

    /// The item with `id`, or `nil` if this pantry has no such item.
    ///
    /// Added because three use cases were finding one item by fetching the
    /// whole pantry and scanning it in Swift - the protocol offered nothing
    /// narrower, so there was nowhere for a real query to live. A store that
    /// can answer this directly should: SwiftData resolves it with a
    /// predicate and a fetch limit of one, and Firestore with a single
    /// `getDocument()` instead of reading the collection.
    func fetch(id: UUID) async throws -> PantryItem?

    /// Items that expire on or before `date`, soonest first.
    ///
    /// Items with no expiry date are **excluded**, not ordered last. An item
    /// nobody dated is not urgent, it is untracked - the same distinction
    /// `IdentifyExpiringInventoryUseCase` already draws in memory. This is
    /// the storage-side form of that rule, so a backend that can evaluate it
    /// does the work instead of the client.
    func fetchExpiring(before date: Date) async throws -> [PantryItem]
}
