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
        return OnlineRecipeMatch(
            recipe: recipe(id: id, title: title, intolerances: intolerances),
            usedIngredientNames: used,
            missedIngredients: missed
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
