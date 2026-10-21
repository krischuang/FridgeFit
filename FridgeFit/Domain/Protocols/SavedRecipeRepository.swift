//
//  SavedRecipeRepository.swift
//  FridgeFit
//

import Foundation

/// Where recipes the user saved from Discover are kept.
///
/// Saved recipes are ordinary `Recipe`s once converted (see
/// `SaveOnlineRecipeUseCase`), so the Recipes page and the feasibility
/// engine treat them exactly like bundled ones.
///
/// ## Why this refines `RecipeRepository`
///
/// `RecipeRepository.fetchAll()` and the read side of this protocol are the
/// same question - "which recipes are available?" - asked of a different
/// store. Declaring the refinement rather than restating the method means a
/// saved-recipe store can be handed straight to `CompositeRecipeRepository`
/// and from there into `GenerateContextAwareRecommendationsUseCase`, with no
/// adapter type and no second ranking engine. The alternative, an identical
/// `fetchAll()` on an unrelated protocol, would have forced a wrapper whose
/// only job was to re-declare conformance.
nonisolated protocol SavedRecipeRepository: RecipeRepository {
    /// Every recipe the signed-in user has saved, newest first.
    func fetchAll() async throws -> [Recipe]

    /// Saves `recipe`, replacing any earlier save with the same id - saving
    /// the same online recipe twice is idempotent.
    ///
    /// - Parameter sourceRecipeID: the provider's (Spoonacular) recipe id,
    ///   kept for reference.
    func save(_ recipe: Recipe, sourceRecipeID: Int) async throws

    /// Removes the saved recipe with `id`. Removing one that isn't saved is
    /// not an error.
    func remove(id: UUID) async throws

    /// Saves `recipe` together with a local copy of its photo, so the saved
    /// recipe can be shown with its picture without going back online.
    /// `nil` image data keeps any photo already stored for this recipe.
    func save(_ recipe: Recipe, sourceRecipeID: Int, imageData: Data?) async throws

    /// The stored photo for a saved recipe, or `nil` if none was saved.
    func imageData(forRecipeID id: UUID) async throws -> Data?

    /// Stored photos for several saved recipes in one call, keyed by recipe
    /// id. Recipes without a photo are simply absent from the result.
    func imageData(forRecipeIDs ids: [UUID]) async throws -> [UUID: Data]
}

/// Defaults for stores that don't keep photos (e.g. Firestore): the recipe
/// is saved without one, and the UI falls back to `Recipe.imageURL`.
nonisolated extension SavedRecipeRepository {
    func save(_ recipe: Recipe, sourceRecipeID: Int, imageData: Data?) async throws {
        try await save(recipe, sourceRecipeID: sourceRecipeID)
    }

    func imageData(forRecipeID id: UUID) async throws -> Data? {
        nil
    }

    /// Fallback for stores without a batch query: one lookup per id.
    func imageData(forRecipeIDs ids: [UUID]) async throws -> [UUID: Data] {
        var result: [UUID: Data] = [:]
        for id in ids {
            if let data = try await imageData(forRecipeID: id) {
                result[id] = data
            }
        }
        return result
    }
}
