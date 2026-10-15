//
//  OnlineRecipeService.swift
//  FridgeFit
//

import Foundation

/// Abstraction over an online recipe provider. `SpoonacularRecipeService`
/// is the production implementation; tests use `MockOnlineRecipeService`.
nonisolated protocol OnlineRecipeService: AnyObject {
    /// Recipes that use some of `criteria.pantryIngredientNames`, honouring
    /// the diet / intolerance / time filters.
    ///
    /// - Throws: `OnlineRecipeSearchError` only - never a raw networking
    ///   error, so the UI always has a human-readable message.
    func searchRecipes(matching criteria: OnlineRecipeSearchCriteria) async throws -> [OnlineRecipeMatch]
}
