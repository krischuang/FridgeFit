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
/// `CompositeRecipeRepository` calls through) are `nonisolated`, but the
/// store is the container's `mainContext`, which is not `Sendable` and must
/// stay on the main actor - see `PersistenceContainer`. So the context lives
/// in `SwiftDataSavedRecipeStore` (`@MainActor`), and this nonisolated
/// wrapper forwards to it; each `await` hops to the main actor. Same one
/// context as the pantry and event repositories.
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
@MainActor
final class SwiftDataSavedRecipeStore {
    private let context: ModelContext
    private let ownerIDProvider: () -> String?
    private let now: () -> Date

    init(context: ModelContext, ownerIDProvider: @escaping () -> String?, now: @escaping () -> Date = { Date() }) {
        self.context = context
        self.ownerIDProvider = ownerIDProvider
        self.now = now
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
            try context.save()
        } catch let error as SaveOnlineRecipeError {
            context.rollback()
            throw error
        } catch {
            context.rollback()
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
            guard let existing = try entity(id: id, ownerID: ownerID) else { return }
            context.delete(existing)
            try context.save()
        } catch {
            context.rollback()
            throw SaveOnlineRecipeError.removeFailed
        }
    }

    // MARK: - Plumbing

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
