//
//  RecipeRepository.swift
//  FridgeFit
//

import Foundation

/// Abstraction over where recipes come from.
///
/// Right now `BundledRecipeRepository` serves a fixed local dataset, but
/// `RecipeViewModel` doesn't need to know that - a future remote/API-backed
/// implementation can conform to the same protocol without touching any
/// use case or view.
nonisolated protocol RecipeRepository: AnyObject {
    /// Every recipe available to browse.
    func fetchAll() async throws -> [Recipe]
}
