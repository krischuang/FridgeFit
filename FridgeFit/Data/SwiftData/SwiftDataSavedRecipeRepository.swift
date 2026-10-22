//
//  SwiftDataSavedRecipeRepository.swift
//  FridgeFit
//

import Foundation
import SwiftData

/// SwiftData-backed `SavedRecipeRepository`: recipes saved from Discover live
/// in the user's on-device store, scoped by `ownerID` like the pantry.
///
/// ## Why two types
///
/// `SavedRecipeRepository` (and `RecipeRepository`, which
/// `CompositeRecipeRepository` calls through) are `nonisolated`, but a
/// `ModelContext` is not `Sendable` and must stay on one actor - see
/// `PersistenceContainer`. So the context lives in
/// `SwiftDataSavedRecipeStore` (`@MainActor`), and this nonisolated wrapper
/// forwards to it; each `await` hops to the main actor. The store makes its
/// own context from the app's single container - see its documentation for
/// why saved recipes do not share the `mainContext`.
nonisolated final class SwiftDataSavedRecipeRepository: SavedRecipeRepository {
    private let store: SwiftDataSavedRecipeStore

    init(store: SwiftDataSavedRecipeStore) {
        self.store = store
    }

    func fetchAll() async throws -> [Recipe] {
        try await store.fetchAll()
    }

    func save(_ recipe: Recipe, sourceRecipeID: Int) async throws {
        try await store.save(recipe, sourceRecipeID: sourceRecipeID, imageData: nil)
    }

    func save(_ recipe: Recipe, sourceRecipeID: Int, imageData: Data?) async throws {
        try await store.save(recipe, sourceRecipeID: sourceRecipeID, imageData: imageData)
    }

    func imageData(forRecipeID id: UUID) async throws -> Data? {
        try await store.imageData(forRecipeID: id)
    }

    func imageData(forRecipeIDs ids: [UUID]) async throws -> [UUID: Data] {
        try await store.imageData(forRecipeIDs: ids)
    }

    func remove(id: UUID) async throws {
        try await store.remove(id: id)
    }
}

/// The main-actor half of `SwiftDataSavedRecipeRepository`.
///
/// Rules:
/// - No signed-in user → `SaveOnlineRecipeError.notAuthenticated`; nothing
///   is read or written without an owner.
/// - Saving an already-saved recipe updates that row in place and replaces
///   its ingredient lines, so there is never a duplicate.
/// - A photo is stored with the recipe when one is given; saving again
///   without one keeps the photo already stored.
/// - Newest save first.
/// - Removing a recipe that isn't saved is not an error.
/// - Store failures surface as `SaveOnlineRecipeError` (`loadFailed` /
///   `saveFailed` / `removeFailed`), never a raw SwiftData error.
/// - A failed write leaves the store exactly as it was, and leaves no other
///   feature's unsaved work affected either - see `context`.
@MainActor
final class SwiftDataSavedRecipeStore {

    /// This feature's own context over the app's single `ModelContainer`.
    ///
    /// ## Why not the shared `mainContext`
    ///
    /// A failed write must leave nothing pending. A half-inserted recipe that
    /// a later commit picks up is worse than the failure itself, and a pending
    /// `delete` left behind by a failed `remove` would eventually drop a
    /// recipe the user still has. What discards that work is
    /// `ModelContext.rollback()` - and rollback is context-wide. On
    /// `PersistenceContainer.mainContext` it would also throw away unsaved
    /// pantry and inventory-event edits; the mirror image is just as bad,
    /// since `save()` there commits *their* pending changes as a side effect
    /// of saving a recipe. On a context of our own, both are exactly scoped.
    ///
    /// Saved recipes can afford their own context because they are a closed
    /// island in the schema: `SavedRecipeEntity` relates only to
    /// `SavedRecipeIngredientEntity`, and nothing else in the app writes
    /// either. The constraint that makes `PersistenceContainer` hand one
    /// shared context to the pantry and event repositories - an
    /// `InventoryEventEntity` can only link to its `PantryItemEntity` when
    /// both are managed by the same context - does not reach this feature.
    /// Same container, so the same store file and the same data; only the
    /// transaction boundary is ours.
    ///
    /// One long-lived context rather than one per call, deliberately: reads
    /// then see this store's own committed writes without depending on
    /// cross-context merge, and an abandoned context can never linger holding
    /// a pending delete of rows a later call goes on to delete for real -
    /// which SwiftData traps on (`This model instance was invalidated because
    /// its backing data could no longer be found`).
    ///
    /// Autosave is off, so every commit is an explicit `save()` and nothing
    /// is committed between one operation and the next.
    private let context: ModelContext
    private let ownerIDProvider: () -> String?
    private let now: () -> Date
    private let willSave: () throws -> Void

    /// - Parameters:
    ///   - container: the app's single container, not its `mainContext`. See
    ///     `context` for why.
    ///   - willSave: runs immediately before each `context.save()`. A no-op
    ///     in the app; tests throw from it to drive the failure paths
    ///     deterministically, which a real SwiftData store cannot be asked
    ///     to do on demand.
    init(
        container: ModelContainer,
        ownerIDProvider: @escaping () -> String?,
        now: @escaping () -> Date = { Date() },
        willSave: @escaping () throws -> Void = {}
    ) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        self.context = context
        self.ownerIDProvider = ownerIDProvider
        self.now = now
        self.willSave = willSave
    }

    func fetchAll() throws -> [Recipe] {
        let ownerID = try requireOwnerID()
        let descriptor = FetchDescriptor<SavedRecipeEntity>(
            predicate: #Predicate { $0.ownerID == ownerID },
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor).map(SavedRecipeMapper.toDomain)
        } catch {
            throw SaveOnlineRecipeError.loadFailed
        }
    }

    func save(_ recipe: Recipe, sourceRecipeID: Int, imageData: Data?) throws {
        let ownerID = try requireOwnerID()
        do {
            let target: SavedRecipeEntity
            if let existing = try entity(id: recipe.id, ownerID: ownerID) {
                SavedRecipeMapper.apply(recipe, sourceRecipeID: sourceRecipeID, to: existing)
                existing.savedAt = now()
                for line in existing.ingredients {
                    context.delete(line)
                }
                existing.ingredients = []
                target = existing
            } else {
                target = SavedRecipeMapper.makeEntity(recipe, ownerID: ownerID, sourceRecipeID: sourceRecipeID, savedAt: now())
                context.insert(target)
            }

            if let imageData {
                target.imageData = imageData
            }

            let lines = SavedRecipeMapper.makeLines(for: recipe)
            for line in lines {
                context.insert(line)
            }
            target.ingredients = lines
            try willSave()
            try context.save()
        } catch let error as SaveOnlineRecipeError {
            discardPendingWork()
            throw error
        } catch {
            discardPendingWork()
            throw SaveOnlineRecipeError.saveFailed
        }
    }

    func imageData(forRecipeID id: UUID) throws -> Data? {
        let ownerID = try requireOwnerID()
        do {
            return try entity(id: id, ownerID: ownerID)?.imageData
        } catch {
            throw SaveOnlineRecipeError.loadFailed
        }
    }

    /// One fetch for all requested recipes of the current owner. Only rows
    /// that actually have a photo are returned. The image bytes live in
    /// external storage and are only read for the rows returned here.
    func imageData(forRecipeIDs ids: [UUID]) throws -> [UUID: Data] {
        guard !ids.isEmpty else { return [:] }
        let ownerID = try requireOwnerID()
        let descriptor = FetchDescriptor<SavedRecipeEntity>(
            predicate: #Predicate { ids.contains($0.recipeID) && $0.ownerID == ownerID }
        )
        do {
            var result: [UUID: Data] = [:]
            for entity in try context.fetch(descriptor) {
                if let data = entity.imageData {
                    result[entity.recipeID] = data
                }
            }
            return result
        } catch {
            throw SaveOnlineRecipeError.loadFailed
        }
    }

    func remove(id: UUID) throws {
        let ownerID = try requireOwnerID()
        do {
            // Removing one that isn't saved is not an error.
            guard let existing = try entity(id: id, ownerID: ownerID) else { return }

            // The lines are detached and deleted explicitly, so the recipe is
            // childless by the time it is deleted and the `.cascade` rule has
            // nothing left to do. This is not tidiness - it is what makes the
            // failure path survivable. Deleting a recipe that still owns its
            // lines leaves a pending cascade that cannot be undone: a
            // `rollback()` traps inside SwiftData snapshotting lines that are
            // still faults (`Unexpected backing data for snapshot creation:
            // _FullFutureBackingData<SavedRecipeIngredientEntity>`), while
            // abandoning the pending delete instead poisons the next attempt
            // (`This model instance was invalidated because its backing data
            // could no longer be found`). Detached, both the delete and its
            // rollback are ordinary row operations.
            //
            // `delete(model:where:)` is not an option here: a batch delete
            // cannot nullify the mandatory inverse and fails outright.
            let lines = existing.ingredients
            existing.ingredients = []
            for line in lines {
                context.delete(line)
            }
            context.delete(existing)
            try willSave()
            try context.save()
        } catch {
            // Without this the delete would stay pending and a later commit
            // would drop a recipe the user still has.
            discardPendingWork()
            throw SaveOnlineRecipeError.removeFailed
        }
    }

    // MARK: - Plumbing

    /// Undoes everything the failed operation did, and only that: the context
    /// is this store's own, so an unrelated pantry or inventory-event edit on
    /// `mainContext` is not in scope. See `context`.
    private func discardPendingWork() {
        context.rollback()
    }

    private func requireOwnerID() throws -> String {
        guard let ownerID = ownerIDProvider(), !ownerID.isEmpty else {
            throw SaveOnlineRecipeError.notAuthenticated
        }
        return ownerID
    }

    private func entity(id: UUID, ownerID: String) throws -> SavedRecipeEntity? {
        var descriptor = FetchDescriptor<SavedRecipeEntity>(
            predicate: #Predicate { $0.recipeID == id && $0.ownerID == ownerID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
