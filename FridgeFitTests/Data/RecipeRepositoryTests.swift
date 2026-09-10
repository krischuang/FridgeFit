//
//  RecipeRepositoryTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class RecipeRepositoryTests: XCTestCase {
    func test_bundledRecipeRepository_loadsAtLeastTenRecipes() async throws {
        let repository = BundledRecipeRepository()

        let recipes = try await repository.fetchAll()

        XCTAssertGreaterThanOrEqual(recipes.count, 8)
    }

    func test_bundledRecipeRepository_recipesHaveIngredientsAndInstructions() async throws {
        let repository = BundledRecipeRepository()

        let recipes = try await repository.fetchAll()

        for recipe in recipes {
            XCTAssertFalse(recipe.ingredients.isEmpty, "\(recipe.title) should have ingredients")
            XCTAssertFalse(recipe.instructions.isEmpty, "\(recipe.title) should have instructions")
        }
    }

    func test_inMemoryRecipeRepository_returnsSeededRecipes() async throws {
        let recipe = Recipe(
            title: "Test Recipe",
            summary: "A recipe for testing.",
            ingredients: [RecipeIngredient(ingredient: Ingredient(name: "Salt", category: .spice), quantity: 1, unit: .grams, role: .essential)],
            instructions: ["Season to taste."]
        )
        let repository = InMemoryRecipeRepository(recipes: [recipe])

        let recipes = try await repository.fetchAll()

        XCTAssertEqual(recipes, [recipe])
    }

    func test_inMemoryRecipeRepository_defaultsToEmpty() async throws {
        let repository = InMemoryRecipeRepository()

        let recipes = try await repository.fetchAll()

        XCTAssertTrue(recipes.isEmpty)
    }
}
