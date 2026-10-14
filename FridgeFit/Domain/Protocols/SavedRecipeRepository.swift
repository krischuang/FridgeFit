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
protocol SavedRecipeRepository: AnyObject {
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
}
