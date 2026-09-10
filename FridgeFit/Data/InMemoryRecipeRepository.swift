//
//  InMemoryRecipeRepository.swift
//  FridgeFit
//

import Foundation

/// Test double for `RecipeRepository` - holds whatever recipes a test
/// seeds it with, so feasibility scenarios can be constructed precisely
/// without depending on `BundledRecipeRepository`'s real dataset.
final class InMemoryRecipeRepository: RecipeRepository {
    private let recipes: [Recipe]

    init(recipes: [Recipe] = []) {
        self.recipes = recipes
    }

    func fetchAll() async throws -> [Recipe] {
        recipes
    }
}
