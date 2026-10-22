//
//  IngredientCoverageConsistencyTests.swift
//  FridgeFitTests
//
//  Discover and Recipes answer the same question - "does the pantry hold
//  what this recipe asks for?" - through two different engines. They used to
//  answer it with two different rules, so a Discover result reading "Matched"
//  could flip to "Missing" the moment it was saved. Both now go through
//  `IngredientNameMatching.covers`, and these tests hold them to it.
//

import XCTest
@testable import FridgeFit

@MainActor
final class IngredientCoverageConsistencyTests: XCTestCase {

    /// Each pair is (pantry name, recipe name, does the pantry cover it?).
    private static let pairs: [(pantry: String, recipe: String, covered: Bool)] = [
        // Folded: case, plural, and leading words that describe how the food
        // was bought or prepared rather than which food it is.
        ("Cheddar Cheese", "mild cheddar cheese", true),
        ("egg", "large eggs", true),
        ("parmesan", "freshly grated parmesan", true),
        ("Milk", "whole milk", true),
        ("spinach", "fresh spinach", true),
        ("butter", "unsalted butter", true),
        ("chicken breast", "boneless skinless chicken breasts", true),

        // Not folded: words that change which food is meant. Each of these
        // would be a false "you have it", which is invisible to the user in
        // a way a missed match is not.
        ("sugar", "brown sugar", false),
        ("potato", "sweet potato", false),
        ("onion", "green onion", false),
        ("milk", "coconut milk", false),
        ("cheese", "cheddar cheese", false),
        ("eggs", "egg whites", false),
        ("cream", "light cream", false),
    ]

    /// Discover's verdict: does the reconciler put the line under "have"?
    ///
    /// The provider reports nothing as used, so only the pantry-match path
    /// can put it there - the same question feasibility asks.
    private func discoverSaysCovered(pantry: String, recipe: String) -> Bool {
        var onlineRecipe = OnlineRecipeFixtures.recipe(id: 1)
        onlineRecipe.ingredients = [OnlineRecipeFixtures.line(recipe, id: 1)]
        let match = OnlineRecipeMatch(
            recipe: onlineRecipe,
            usedIngredientNames: [],
            missedIngredients: onlineRecipe.ingredients
        )

        let reconciled = OnlineRecipePantryReconciler.reconciled(
            match,
            pantry: [PantryItem(ingredient: Ingredient(name: pantry, category: .other), quantity: 1, unit: .pieces)]
        )
        return reconciled.usedIngredientNames == [recipe]
    }

    /// Recipes' verdict: does feasibility call the ingredient available?
    private func savedRecipesSayCovered(pantry: String, recipe: String) -> Bool {
        let result = EvaluateRecipeFeasibilityUseCase.evaluate(
            recipe: Recipe(
                title: "Consistency",
                summary: "",
                ingredients: [
                    RecipeIngredient(ingredient: Ingredient(name: recipe), quantity: 1, unit: .pieces, role: .essential),
                ],
                instructions: ["Cook it."]
            ),
            against: [PantryItem(ingredient: Ingredient(name: pantry), quantity: 1, unit: .pieces)]
        )
        return result.evaluatedIngredients.first?.availability == .available
    }

    func test_discoverAndSavedRecipes_agreeOnEveryPair() {
        for pair in Self.pairs {
            let discover = discoverSaysCovered(pantry: pair.pantry, recipe: pair.recipe)
            let savedRecipes = savedRecipesSayCovered(pantry: pair.pantry, recipe: pair.recipe)

            XCTAssertEqual(
                discover,
                savedRecipes,
                "Discover and Recipes disagree about pantry \"\(pair.pantry)\" vs recipe \"\(pair.recipe)\""
            )
            XCTAssertEqual(
                discover,
                pair.covered,
                "pantry \"\(pair.pantry)\" vs recipe \"\(pair.recipe)\" should be \(pair.covered ? "covered" : "missing")"
            )
        }
    }

    /// The shared rule is the one both engines call, so it must give the
    /// same answers directly.
    func test_sharedCoverageRule_matchesBothEngines() {
        for pair in Self.pairs {
            XCTAssertEqual(
                IngredientNameMatching.covers(pantryName: pair.pantry, recipeName: pair.recipe),
                pair.covered,
                "covers(\"\(pair.pantry)\", \"\(pair.recipe)\")"
            )
        }
    }

    /// Coverage is the looser of the two questions. The strict one - "is this
    /// the same pantry entry?" - must stay strict, so someone can keep
    /// "fresh basil" and "dried basil" as separate items with separate
    /// expiry dates.
    func test_sameEntryRule_staysStricterThanCoverage() {
        XCTAssertTrue(IngredientNameMatching.covers(pantryName: "basil", recipeName: "fresh basil"))
        XCTAssertFalse(IngredientNameMatching.matches("fresh basil", "basil"))

        XCTAssertTrue(IngredientNameMatching.covers(pantryName: "Cheddar Cheese", recipeName: "mild cheddar cheese"))
        XCTAssertFalse(IngredientNameMatching.matches("mild cheddar cheese", "Cheddar Cheese"))

        // Plurals and case are folded by both.
        XCTAssertTrue(IngredientNameMatching.matches("Eggs", "egg"))
        XCTAssertTrue(IngredientNameMatching.covers(pantryName: "Eggs", recipeName: "egg"))
    }
}
