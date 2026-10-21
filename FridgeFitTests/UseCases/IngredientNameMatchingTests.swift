//
//  IngredientNameMatchingTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class IngredientNameMatchingTests: XCTestCase {

    // MARK: - Same ingredient

    func test_singularAndPlural_match() {
        XCTAssertTrue(IngredientNameMatching.matches("egg", "Eggs"))
        XCTAssertTrue(IngredientNameMatching.matches("Tomatoes", "tomato"))
        XCTAssertTrue(IngredientNameMatching.matches("berries", "Berry"))
        XCTAssertTrue(IngredientNameMatching.matches("Peaches", "peach"))
        XCTAssertTrue(IngredientNameMatching.matches("radishes", "Radish"))
        XCTAssertTrue(IngredientNameMatching.matches("bay leaves", "Bay Leaf"))
        XCTAssertTrue(IngredientNameMatching.matches("Cherry Tomatoes", "cherry tomato"))
        XCTAssertTrue(IngredientNameMatching.matches("Chicken Breasts", "chicken breast"))
    }

    func test_caseAndWhitespace_stillMatch() {
        XCTAssertTrue(IngredientNameMatching.matches("  Greek   Yogurt ", "greek yogurt"))
    }

    func test_wordsThatOnlyLookPlural_areLeftAlone() {
        XCTAssertEqual(IngredientNameMatching.singularized("hummus"), "hummus")
        XCTAssertEqual(IngredientNameMatching.singularized("asparagus"), "asparagus")
        XCTAssertEqual(IngredientNameMatching.singularized("swiss"), "swiss")
        XCTAssertTrue(IngredientNameMatching.matches("Hummus", "hummus"))
    }

    // MARK: - Different ingredients must stay different

    func test_neverMatchesByDroppingOrAddingWords() {
        XCTAssertFalse(IngredientNameMatching.matches("coconut milk", "Milk"))
        XCTAssertFalse(IngredientNameMatching.matches("green onions", "Onion"))
        XCTAssertFalse(IngredientNameMatching.matches("fresh spinach", "Spinach"))
        XCTAssertFalse(IngredientNameMatching.matches("egg whites", "Eggs"))
    }

    func test_emptyNames_neverMatch() {
        XCTAssertFalse(IngredientNameMatching.matches("", ""))
        XCTAssertFalse(IngredientNameMatching.matches("   ", "  "))
    }

    // MARK: - Through the app

    /// The reported bug: pantry "egg", recipe "Eggs" read as missing.
    func test_feasibility_pantryEgg_coversRecipeEggs() async throws {
        let pantry = InMemoryPantryRepository(seedItems: [
            PantryItem(ingredient: Ingredient(name: "egg"), quantity: 6, unit: .pieces),
        ])
        let recipe = Recipe(
            title: "Omelette",
            summary: "",
            ingredients: [RecipeIngredient(ingredient: Ingredient(name: "Eggs"), quantity: 2, unit: .pieces, role: .essential)],
            instructions: ["Whisk and cook."]
        )

        let result = try await EvaluateRecipeFeasibilityUseCase(pantryRepository: pantry).execute(recipe: recipe)

        XCTAssertEqual(result.evaluatedIngredients.first?.availability, .available)
        XCTAssertEqual(result.status, .makeable)
    }

    func test_addPantryItem_treatsSingularAndPluralAsTheSameItem() async {
        let pantry = InMemoryPantryRepository(seedItems: [
            PantryItem(ingredient: Ingredient(name: "Eggs"), quantity: 6, unit: .pieces),
        ])
        do {
            _ = try await AddPantryItemUseCase(pantryRepository: pantry).execute(name: "egg", quantity: 2, unit: .pieces, category: .other)
            XCTFail("Expected duplicateIngredient")
        } catch {
            XCTAssertEqual(error as? AddPantryItemError, .duplicateIngredient(name: "Eggs"))
        }
    }

    func test_discoverExpiryRanking_usesTheSameRule() {
        XCTAssertTrue(OnlineRecipeExpiryRanking.namesMatch("eggs", "Egg"))
        XCTAssertTrue(OnlineRecipeExpiryRanking.namesMatch("bay leaves (dried)", "Bay Leaf"))
        XCTAssertFalse(OnlineRecipeExpiryRanking.namesMatch("coconut milk", "Milk"))
    }
}
