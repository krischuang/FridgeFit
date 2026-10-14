//
//  FirestoreSavedRecipeRepositoryMappingTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class FirestoreSavedRecipeRepositoryMappingTests: XCTestCase {
    private func sampleRecipe() -> Recipe {
        Recipe(
            id: SaveOnlineRecipeUseCase.savedRecipeID(forOnlineRecipeID: 99),
            title: "Garlic Pasta",
            summary: "Quick.",
            servings: 2,
            ingredients: [RecipeIngredient(ingredient: Ingredient(name: "Pasta"), quantity: 250, unit: .grams, role: .essential)],
            instructions: ["Boil."],
            symbolName: "globe"
        )
    }

    func test_encodeThenDecode_roundTrips() throws {
        let recipe = sampleRecipe()
        let data = try FirestoreSavedRecipeRepository.encode(recipe, sourceRecipeID: 99)

        XCTAssertEqual(data["sourceRecipeID"] as? Int, 99)
        XCTAssertEqual(data["title"] as? String, "Garlic Pasta")
        XCTAssertNotNil(data["savedAt"])
        XCTAssertEqual(FirestoreSavedRecipeRepository.decode(id: recipe.id.uuidString, data: data), recipe)
    }

    func test_decode_rejectsMalformedOrMismatchedDocuments() throws {
        let recipe = sampleRecipe()
        let data = try FirestoreSavedRecipeRepository.encode(recipe, sourceRecipeID: 99)

        XCTAssertNil(FirestoreSavedRecipeRepository.decode(id: "not-a-uuid", data: data))
        XCTAssertNil(FirestoreSavedRecipeRepository.decode(id: UUID().uuidString, data: data), "Stored recipe must belong to its document")
        XCTAssertNil(FirestoreSavedRecipeRepository.decode(id: recipe.id.uuidString, data: ["recipeJSON": "{broken"]))
        XCTAssertNil(FirestoreSavedRecipeRepository.decode(id: recipe.id.uuidString, data: [:]))
    }
}
