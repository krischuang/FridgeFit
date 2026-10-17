//
//  PantryRepository.swift
//  FridgeFit
//

import Foundation

/// Abstraction over where the pantry is stored. Use cases depend on this
/// protocol, not a concrete storage type, so swapping the in-memory test
/// double for `FirestorePantryRepository` doesn't require touching any use
/// case.
nonisolated protocol PantryRepository: AnyObject {
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
}
