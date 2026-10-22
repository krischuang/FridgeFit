//
//  BundledPhotoAssetsTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

// photos in Assets.xcassets for bundled recipes and fridge categories. the main
// thing these catch is someone renaming a recipe (or adding one) and the photo
// quietly falling back to the symbol.
@MainActor
final class BundledPhotoAssetsTests: XCTestCase {

    func test_everyBundledRecipe_hasAPhoto() async throws {
        let recipes = try await BundledRecipeRepository().fetchAll()
        XCTAssertFalse(recipes.isEmpty)

        let missing = recipes.filter { BundledPhotoAssets.recipePhoto(for: $0) == nil }.map(\.title)
        XCTAssertEqual(missing, [], "No photo in Assets for: \(missing)")
    }

    func test_everyCategory_hasAPhoto() async {
        let missing = IngredientCategory.allCases.filter { BundledPhotoAssets.categoryPhoto(for: $0) == nil }
        XCTAssertEqual(missing, [])
    }

    func test_slug_matchesTheAssetNames() async {
        XCTAssertEqual(BundledPhotoAssets.slug("Creamy Chicken Pasta"), "creamy_chicken_pasta")
        XCTAssertEqual(BundledPhotoAssets.slug("Rice and Beans"), "rice_and_beans")
        // punctuation and doubled spaces don't leave stray underscores
        XCTAssertEqual(BundledPhotoAssets.slug("  Mac & Cheese!! "), "mac_cheese")
    }

    func test_unknownRecipe_hasNoPhoto_soTheSymbolStays() async {
        let recipe = Recipe(title: "Something Nobody Photographed", summary: "", ingredients: [], instructions: [])
        XCTAssertNil(BundledPhotoAssets.recipePhoto(for: recipe))
    }

    func test_recipeViewModel_showsTheBundledPhoto_forABundledRecipe() async throws {
        let recipes = try await BundledRecipeRepository().fetchAll()
        let recipe = try XCTUnwrap(recipes.first)
        let model = RecipeViewModel(recipeRepository: InMemoryRecipeRepository(recipes: [recipe]),
                                    pantryRepository: InMemoryPantryRepository())

        XCTAssertNotNil(model.thumbnail(for: recipe))
        XCTAssertNotNil(model.heroImage(for: recipe))
    }

    // a recipe saved from Discover has its own photo URL - the bundled one must
    // not jump in front of it, even if the titles happen to match
    func test_recipeWithItsOwnPhotoURL_doesntGetTheBundledPhoto() async {
        let saved = Recipe(title: "Tomato Soup", summary: "", ingredients: [], instructions: [],
                           imageURL: URL(string: "https://example.com/soup.jpg"))
        let model = RecipeViewModel(recipeRepository: InMemoryRecipeRepository(recipes: []),
                                    pantryRepository: InMemoryPantryRepository())

        XCTAssertNil(model.thumbnail(for: saved))
        XCTAssertNil(model.heroImage(for: saved))
    }
}
