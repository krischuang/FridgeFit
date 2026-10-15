//
//  InMemorySavedRecipeRepository.swift
//  FridgeFit
//

import Foundation

/// In-memory `SavedRecipeRepository` for previews and tests.
nonisolated final class InMemorySavedRecipeRepository: SavedRecipeRepository {
    private(set) var recipes: [Recipe]
    private(set) var sourceIDs: [UUID: Int] = [:]
    /// When set, every call throws this - for failure-path tests.
    var failure: Error?

    init(recipes: [Recipe] = []) {
        self.recipes = recipes
    }

    func fetchAll() async throws -> [Recipe] {
        if let failure { throw failure }
        return recipes
    }

    func save(_ recipe: Recipe, sourceRecipeID: Int) async throws {
        if let failure { throw failure }
        recipes.removeAll { $0.id == recipe.id }
        recipes.insert(recipe, at: 0)
        sourceIDs[recipe.id] = sourceRecipeID
    }

    func remove(id: UUID) async throws {
        if let failure { throw failure }
        recipes.removeAll { $0.id == id }
        sourceIDs[id] = nil
    }
}
