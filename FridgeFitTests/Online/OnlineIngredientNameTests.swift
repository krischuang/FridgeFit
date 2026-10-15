//
//  OnlineIngredientNameTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// Covers the conservative tidying applied to provider ingredient names,
/// and - just as importantly - pins the equivalences it refuses to make.
@MainActor
final class OnlineIngredientNameTests: XCTestCase {

    // MARK: - What it does

    func test_trimsSurroundingWhitespace() {
        XCTAssertEqual(OnlineIngredientName.normalized("  garlic  "), "garlic")
    }

    func test_collapsesInternalWhitespace() {
        XCTAssertEqual(OnlineIngredientName.normalized("spring\t  onions"), "spring onions")
    }

    func test_removesParentheticalAsides() {
        XCTAssertEqual(OnlineIngredientName.normalized("tomatoes (14 oz can)"), "tomatoes")
        XCTAssertEqual(OnlineIngredientName.normalized("flour (plain)"), "flour")
        XCTAssertEqual(
            OnlineIngredientName.normalized("milk (whole) (organic)"),
            "milk",
            "More than one aside is still just packaging detail"
        )
    }

    func test_emptyOrPunctuationOnlyInputYieldsEmptyString() {
        XCTAssertEqual(OnlineIngredientName.normalized(""), "")
        XCTAssertEqual(OnlineIngredientName.normalized("   "), "")
        XCTAssertEqual(OnlineIngredientName.normalized("(only an aside)"), "")
    }

    func test_displayNameTitleCasesWithoutShouting() {
        XCTAssertEqual(OnlineIngredientName.displayName("spring onions"), "Spring Onions")
        XCTAssertEqual(OnlineIngredientName.displayName("OLIVE OIL"), "Olive Oil")
        XCTAssertEqual(OnlineIngredientName.displayName("  parmesan  cheese "), "Parmesan Cheese")
    }

    // MARK: - What it deliberately does not do

    func test_doesNotSingularise() {
        // "garlic cloves" must not be folded onto "garlic": that would make
        // the feasibility engine report a pantry item the user may not have.
        XCTAssertEqual(OnlineIngredientName.normalized("garlic cloves"), "garlic cloves")
        XCTAssertNotEqual(OnlineIngredientName.normalized("garlic cloves"), "garlic")
    }

    func test_doesNotStripPreparationOrVarietyWords() {
        XCTAssertEqual(OnlineIngredientName.normalized("green onion"), "green onion")
        XCTAssertEqual(OnlineIngredientName.normalized("ground almonds"), "ground almonds")
        XCTAssertEqual(OnlineIngredientName.normalized("coconut milk"), "coconut milk")
    }

    func test_distinctIngredientsStayDistinct() {
        // The property that keeps name tidying from becoming a quantity
        // claim: nothing here maps two different foods onto one name.
        let names = ["coconut milk", "milk", "green onion", "onion", "garlic cloves", "garlic"]
        let normalized = names.map(OnlineIngredientName.normalized)

        XCTAssertEqual(Set(normalized).count, names.count, "Normalisation collapsed two distinct ingredients")
    }

    // MARK: - Applied at the mapping boundary

    func test_savedRecipeUsesTidiedDisplayNames() throws {
        let online = OnlineRecipe(
            id: 1,
            title: "Test",
            imageURL: nil,
            readyInMinutes: nil,
            servings: nil,
            summary: nil,
            sourceName: nil,
            sourceURL: nil,
            healthScore: nil,
            diets: [],
            ingredients: [
                OnlineRecipeIngredient(
                    providerID: 1,
                    name: "  tomatoes (14 oz can) ",
                    amount: 400,
                    unit: .grams,
                    originalUnit: "g"
                ),
            ],
            steps: ["Cook."],
            containsIntolerances: []
        )

        let recipe = try SaveOnlineRecipeUseCase.recipe(from: online)

        XCTAssertEqual(recipe.ingredients.first?.ingredient.name, "Tomatoes")
    }

    func test_duplicateNamesCollapseToTheFirstLine() throws {
        // Feasibility matches by name, so two lines with the same name would
        // double-count. The first wins.
        let online = OnlineRecipe(
            id: 2,
            title: "Test",
            imageURL: nil,
            readyInMinutes: nil,
            servings: nil,
            summary: nil,
            sourceName: nil,
            sourceURL: nil,
            healthScore: nil,
            diets: [],
            ingredients: [
                OnlineRecipeIngredient(providerID: 1, name: "Butter", amount: 50, unit: .grams, originalUnit: "g"),
                OnlineRecipeIngredient(providerID: 1, name: "butter", amount: 20, unit: .grams, originalUnit: "g"),
            ],
            steps: ["Cook."],
            containsIntolerances: []
        )

        let recipe = try SaveOnlineRecipeUseCase.recipe(from: online)

        XCTAssertEqual(recipe.ingredients.count, 1)
        XCTAssertEqual(recipe.ingredients.first?.quantity, 50)
    }
}
