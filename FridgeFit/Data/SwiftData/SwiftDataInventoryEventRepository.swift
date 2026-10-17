//
//  SwiftDataInventoryEventRepository.swift
//  FridgeFit
//

import Foundation
import SwiftData

/// SwiftData-backed implementation of `InventoryEventRepository`.
///
/// Shares the `ModelContext` with `SwiftDataPantryRepository`, which is what
/// allows `append` to link a new event to the pantry item it describes -
/// objects in different contexts cannot be related.
///
/// Scoped by `ownerID` on every call, for the reason set out in
/// `SwiftDataPantryRepository`.
@MainActor
final class SwiftDataInventoryEventRepository: InventoryEventRepository {
    private let context: ModelContext
    private let ownerIDProvider: () -> String?

    init(context: ModelContext, ownerIDProvider: @escaping () -> String?) {
        self.context = context
        self.ownerIDProvider = ownerIDProvider
    }

    /// Reuses the pantry's error rather than inventing a second one - it is
    /// the same condition with the same message, which is the choice
    /// `FirestoreInventoryEventRepository` already made.
    private func requireOwnerID() throws -> String {
        guard let ownerID = ownerIDProvider(), !ownerID.isEmpty else {
            throw PantryRepositoryError.notAuthenticated
        }
        return ownerID
    }

    /// Most recent first, capped at `limit`.
    ///
    /// The limit is applied by the fetch, not after it: the activity log only
    /// grows, and reading all of it to show the newest 200 would get slower
    /// every time the user cooks.
    ///
    /// A row whose `kind` this build cannot read is skipped by
    /// `InventoryEventMapper.toDomain` rather than guessed at.
    func fetchAll(limit: Int) async throws -> [InventoryEvent] {
        let ownerID = try requireOwnerID()
        var descriptor = FetchDescriptor<InventoryEventEntity>(
            predicate: #Predicate { $0.ownerID == ownerID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try fetch(descriptor).compactMap(InventoryEventMapper.toDomain)
    }

    /// Appends one event, linked to its pantry item when that item still
    /// exists.
    ///
    /// `item` is `nil` for `finished`, `discarded` and `deleted`, because
    /// `RecordFoodOutcomeUseCase` removes the pantry item before writing the
    /// event. That is expected, not a failure: `pantryItemID` and `itemName`
    /// are stored on the event precisely so the history still reads correctly
    /// without the relationship.
    func append(_ event: InventoryEvent) async throws {
        let ownerID = try requireOwnerID()
        let item = try pantryEntity(id: event.pantryItemID, ownerID: ownerID)
        context.insert(InventoryEventMapper.makeEntity(event, ownerID: ownerID, item: item))
        try save()
    }

    /// Deletes events by id - used only to undo an action the user just took.
    ///
    /// Deleted in one `save()` so an undo either removes every event it
    /// created or none of them. A half-undone action would leave history
    /// claiming something happened that was rolled back, which is the
    /// guarantee `FirestoreInventoryEventRepository` gets from a write batch.
    ///
    /// Ids that are not present are ignored rather than treated as an error:
    /// undo is a best-effort correction, and failing it because one event was
    /// already gone would leave the user stuck.
    func remove(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        let ownerID = try requireOwnerID()
        let removing = Set(ids)
        let descriptor = FetchDescriptor<InventoryEventEntity>(
            predicate: #Predicate { event in
                event.ownerID == ownerID && removing.contains(event.id)
            }
        )
        for entity in try fetch(descriptor) {
            context.delete(entity)
        }
        try save()
    }

    // MARK: - Storage plumbing

    /// The pantry item an event refers to, or `nil` if it has been removed.
    private func pantryEntity(id: UUID, ownerID: String) throws -> PantryItemEntity? {
        var descriptor = FetchDescriptor<PantryItemEntity>(
            predicate: #Predicate { $0.id == id && $0.ownerID == ownerID }
        )
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
        do {
            return try context.fetch(descriptor)
        } catch {
            throw PantryRepositoryError.storageUnavailable
        }
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            throw PantryRepositoryError.storageUnavailable
        }
    }
}
