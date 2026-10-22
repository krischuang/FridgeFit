//
//  OnlineRecipeFixtures.swift
//  FridgeFitTests
//

import Foundation
@testable import FridgeFit

/// Shared fixtures for the online-recipe suites.
///
/// Deliberately not `@MainActor`: these are pure value constructors over
/// nonisolated model types, and several suites use them in default argument
/// expressions, which are evaluated in a nonisolated context.
enum OnlineRecipeFixtures {
    static func recipe(
        id: Int = 1,
        title: String = "Garlic Chicken",
        intolerances: Set<FoodIntolerance>? = []
    ) -> OnlineRecipe {
        OnlineRecipe(
            id: id,
            title: title,
            imageURL: nil,
            readyInMinutes: 25,
            servings: 2,
            summary: "Quick dinner.",
            sourceName: nil,
            sourceURL: nil,
            healthScore: nil,
            diets: [],
            ingredients: [
                OnlineRecipeIngredient(providerID: 1, name: "chicken", amount: 300, unit: .grams, originalUnit: "g"),
                OnlineRecipeIngredient(providerID: 2, name: "garlic", amount: 2, unit: .pieces, originalUnit: "cloves"),
            ],
            steps: ["Cook it."],
            containsIntolerances: intolerances
        )
    }

    static func match(
        id: Int = 1,
        title: String = "Garlic Chicken",
        intolerances: Set<FoodIntolerance>? = [],
        used: [String] = ["chicken"],
        missedCount: Int = 1
    ) -> OnlineRecipeMatch {
        let missed = (0 ..< missedCount).map {
            OnlineRecipeIngredient(providerID: 100 + $0, name: "missing \($0)", amount: 1, unit: .pieces, originalUnit: "")
        }
        // Like a real provider response, the recipe's ingredient list is the
        // used lines plus the missed lines - so re-deriving have/missing from
        // the pantry (`OnlineRecipePantryReconciler`) gives the same counts.
        var fixtureRecipe = recipe(id: id, title: title, intolerances: intolerances)
        fixtureRecipe.ingredients = used.enumerated().map { index, name in
            OnlineRecipeIngredient(providerID: 10 + index, name: name, amount: 1, unit: .pieces, originalUnit: "")
        } + missed
        return OnlineRecipeMatch(
            recipe: fixtureRecipe,
            usedIngredientNames: used,
            missedIngredients: missed
        )
    }

    /// One ingredient line, for suites that build a recipe's list by hand.
    static func line(_ name: String, id: Int) -> OnlineRecipeIngredient {
        OnlineRecipeIngredient(providerID: id, name: name, amount: 1, unit: .pieces, originalUnit: "")
    }

    /// Spoonacular's shape for the reported Discover bug: brown sugar is in
    /// the ingredient list but in neither `used` nor `missed`, because the
    /// provider assumes pantry staples are owned. Reconciling against a
    /// pantry that holds only an egg must therefore read 1 matched, 3
    /// missing - not the provider's 1 and 2.
    static func bakedCustard() -> OnlineRecipeMatch {
        var custard = recipe(id: 641_000, title: "Baked Custard")
        custard.ingredients = [
            line("eggs", id: 1123),
            line("brown sugar", id: 19334),
            line("milk", id: 1077),
            line("vanilla extract", id: 2050),
        ]
        return OnlineRecipeMatch(
            recipe: custard,
            usedIngredientNames: ["eggs"],
            missedIngredients: [line("milk", id: 1077), line("vanilla extract", id: 2050)]
        )
    }

    static func pantry(_ names: String...) -> InMemoryPantryRepository {
        InMemoryPantryRepository(seedItems: names.map {
            PantryItem(ingredient: Ingredient(name: $0, category: .other), quantity: 1, unit: .pieces)
        })
    }

    /// Trimmed-down but real-shaped `complexSearch` response.
    static let searchResponseJSON = """
    {
      "results": [
        {
          "id": 716429,
          "title": "Pasta with Garlic, Scallions & Cheese",
          "image": "https://img.spoonacular.com/recipes/716429-312x231.jpg",
          "readyInMinutes": 45,
          "servings": 2,
          "sourceUrl": "https://example.com/pasta",
          "sourceName": "Example Kitchen",
          "summary": "A <b>quick</b> pasta &amp; cheese dish.",
          "healthScore": 19,
          "diets": ["lacto ovo vegetarian"],
          "glutenFree": false,
          "dairyFree": false,
          "vegan": false,
          "vegetarian": true,
          "extendedIngredients": [
            {"id": 1001, "name": "butter", "nameClean": "butter", "amount": 1, "unit": "tbsp"},
            {"id": 11215, "name": "garlic", "nameClean": "garlic", "amount": 5, "unit": "cloves"},
            {"id": 20420, "name": "pasta", "nameClean": "pasta", "amount": 0.5, "unit": "kg"},
            {"id": 11291, "name": "scallions", "nameClean": "spring onions", "amount": 4, "unit": "servings"}
          ],
          "analyzedInstructions": [
            {"name": "", "steps": [
              {"number": 1, "step": "Boil the pasta."},
              {"number": 2, "step": "Melt the butter with garlic."}
            ]}
          ],
          "usedIngredients": [
            {"id": 11215, "name": "garlic", "amount": 5, "unit": "cloves"}
          ],
          "missedIngredients": [
            {"id": 20420, "name": "pasta", "amount": 0.5, "unit": "kg"},
            {"id": 1001, "name": "butter", "amount": 1, "unit": "tbsp"}
          ]
        }
      ],
      "offset": 0,
      "number": 1,
      "totalResults": 1
    }
    """
}
