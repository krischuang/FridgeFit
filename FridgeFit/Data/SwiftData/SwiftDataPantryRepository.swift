//
//  SwiftDataPantryRepository.swift
//  FridgeFit
//

import Foundation
import SwiftData

/// SwiftData-backed implementation of `PantryRepository`.
///
/// ## Scoping
///
/// Every read and write is filtered by `ownerID`, resolved per call from
/// `ownerIDProvider`. This is the local equivalent of Firestore's
/// `users/{uid}` path, and it has to be enforced here because a SQLite file
/// has no security rules: without the clause, signing out and signing in as
/// someone else would show that person the previous account's pantry. A
/// missing owner throws `PantryRepositoryError.notAuthenticated` rather than
/// falling back to an unscoped query - the same refusal
/// `FirestorePantryRepository` makes, for the same reason.
///
/// The provider is injected rather than reading `Auth.auth()` here, so this
/// type - and therefore the whole SwiftData layer - has no Firebase
/// dependency. `AppDependencies` supplies the real one.
///
/// ## Isolation
///
/// `@MainActor`, holding the container's `mainContext`. `ModelContext` is not
/// `Sendable`, so it has to be confined; the main actor is where every caller
/// already is. The `async` protocol requirements are satisfied by isolated
/// methods, which is legal and means a caller on another actor simply awaits
/// a hop. See `PersistenceContainer` for why there is no `@ModelActor`.
@MainActor
final class SwiftDataPantryRepository: PantryRepository {
    private let context: ModelContext
    private let ownerIDProvider: () -> String?

    init(context: ModelContext, ownerIDProvider: @escaping () -> String?) {
        self.context = context
        self.ownerIDProvider = ownerIDProvider
    }

    /// - Throws: `PantryRepositoryError.notAuthenticated` when there is no
    ///   signed-in user. Never returns an unscoped result.
    private func requireOwnerID() throws -> String {
        guard let ownerID = ownerIDProvider(), !ownerID.isEmpty else {
            throw PantryRepositoryError.notAuthenticated
        }
        return ownerID
    }

    // MARK: - Reading

    /// Every item in this owner's pantry, ordered by name.
    ///
    /// Sorted in the fetch rather than afterwards, matching the
    /// `order(by: "ingredientName")` the Firestore implementation sends, so
    /// the two backends hand the same order to the same view models.
    func fetchAll() async throws -> [PantryItem] {
        let ownerID = try requireOwnerID()
        let descriptor = FetchDescriptor<PantryItemEntity>(
            predicate: #Predicate { $0.ownerID == ownerID },
            sortBy: [SortDescriptor(\.ingredientName, order: .forward)]
        )
        return try fetch(descriptor).map(PantryItemMapper.toDomain)
    }

    /// One item by id, or `nil`.
    ///
    /// Exists so the use cases that need a single item stop reading the whole
    /// pantry and scanning it in Swift - `RecordIngredientUseUseCase` and
    /// `RecordFoodOutcomeUseCase` both did, because the protocol offered
    /// nothing narrower.
    func fetch(id: UUID) async throws -> PantryItem? {
        try entity(id: id, ownerID: try requireOwnerID()).map(PantryItemMapper.toDomain)
    }

    /// Items that expire on or before `date`, soonest first.
    ///
    /// Items with no expiry date are excluded, not sorted last: an item
    /// nobody dated is not urgent, it is untracked. That is the same rule
    /// `IdentifyExpiringInventoryUseCase` applies in memory - this is the
    /// storage-side form of it, expressed as a predicate the database can
    /// evaluate.
    func fetchExpiring(before date: Date) async throws -> [PantryItem] {
        let ownerID = try requireOwnerID()
        // Undated items are excluded by coalescing their missing date to the
        // distant future, which is always outside the window.
        //
        // Written this way because SwiftData has to translate the predicate
        // into a store query, and it cannot lower a force-unwrap - the
        // apparently equivalent `expiryDate != nil && expiryDate! <= date`
        // compiles and then fails at fetch time. `??` maps onto a nil-coalesce
        // expression the store understands.
        let unbounded = Date.distantFuture
        let descriptor = FetchDescriptor<PantryItemEntity>(
            predicate: #Predicate { item in
                item.ownerID == ownerID && (item.expiryDate ?? unbounded) <= date
            },
            sortBy: [
                SortDescriptor(\.expiryDate, order: .forward),
                SortDescriptor(\.ingredientName, order: .forward),
            ]
        )
        return try fetch(descriptor).map(PantryItemMapper.toDomain)
    }

    // MARK: - Writing

    func add(_ item: PantryItem) async throws {
        let ownerID = try requireOwnerID()
        context.insert(PantryItemMapper.makeEntity(item, ownerID: ownerID))
        try save()
    }

    /// - Throws: `UpdatePantryItemError.itemNotFound` if this owner has no
    ///   item with `item.id`.
    func update(_ item: PantryItem) async throws {
        let ownerID = try requireOwnerID()
        guard let existing = try entity(id: item.id, ownerID: ownerID) else {
            throw UpdatePantryItemError.itemNotFound
        }
        // Mutated in place rather than replaced: see `PantryItemMapper.apply`.
        PantryItemMapper.apply(item, to: existing)
        try save()
    }

    /// - Throws: `RemovePantryItemError.pantryItemNotFound` if this owner has
    ///   no item with `id`.
    ///
    /// The item's events are *not* deleted with it - the relationship is
    /// nullified. That is what lets `RecordFoodOutcomeUseCase` remove an item
    /// and still record that it was finished. See `PantryItemEntity.events`.
    func remove(id: UUID) async throws {
        let ownerID = try requireOwnerID()
        guard let existing = try entity(id: id, ownerID: ownerID) else {
            throw RemovePantryItemError.pantryItemNotFound
        }
        context.delete(existing)
        try save()
    }

    // MARK: - Storage plumbing

    /// Fetches one entity by id, still scoped by owner.
    ///
    /// The owner clause is not redundant beside a unique id: without it, a
    /// caller signed in as one account could update or delete a row belonging
    /// to another simply by knowing its id.
    private func entity(id: UUID, ownerID: String) throws -> PantryItemEntity? {
        var descriptor = FetchDescriptor<PantryItemEntity>(
            predicate: #Predicate { $0.id == id && $0.ownerID == ownerID }
        )
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    /// Wraps SwiftData's own failures in a domain error.
    ///
    /// Callers - use cases and view models - should never have to pattern
    /// match on a storage framework's error type to decide what to tell the
    /// user, and `PantryRepositoryError` is what the Firestore path already
    /// throws for conditions of this kind.
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
            // Leaves the context's pending changes in place rather than
            // rolling back: the caller is about to surface the failure, and
            // a retry should not have to re-enter the data.
            throw PantryRepositoryError.storageUnavailable
        }
    }
}
