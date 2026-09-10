//
//  BundledRecipeRepository.swift
//  FridgeFit
//

import Foundation

/// Local/offline implementation of `RecipeRepository`.
///
/// Phase 2 doesn't have a remote recipe API yet, so this ships a fixed,
/// realistic dataset - varied enough in ingredients, units, and
/// essential/optional mixes to exercise every feasibility outcome against
/// a real pantry.
final class BundledRecipeRepository: RecipeRepository {
    private let recipes: [Recipe]

    init(recipes: [Recipe] = BundledRecipeRepository.sampleRecipes) {
        self.recipes = recipes
    }

    func fetchAll() async throws -> [Recipe] {
        recipes
    }
}

extension BundledRecipeRepository {
    static var sampleRecipes: [Recipe] {
        [
            Recipe(
                title: "Creamy Chicken Pasta",
                summary: "A rich stovetop pasta with a simple cream sauce.",
                servings: 2,
                ingredients: [
                    RecipeIngredient(ingredient: Ingredient(name: "Chicken Breast", category: .meat), quantity: 400, unit: .grams, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Pasta", category: .grain), quantity: 250, unit: .grams, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Garlic", category: .produce), quantity: 2, unit: .pieces, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Cream", category: .dairy), quantity: 200, unit: .milliliters, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Parsley", category: .produce), quantity: 1, unit: .tablespoons, role: .optional),
                ],
                instructions: [
                    "Cook the pasta in salted boiling water until al dente.",
                    "Sear the chicken breast and slice once cooked through.",
                    "Sauté garlic, then stir in the cream and simmer.",
                    "Toss the pasta and chicken through the sauce.",
                    "Garnish with parsley if you have it.",
                ],
                symbolName: "fork.knife"
            ),
            Recipe(
                title: "Vegetable Fried Rice",
                summary: "A quick weeknight stir-fry using pantry staples.",
                servings: 3,
                ingredients: [
                    RecipeIngredient(ingredient: Ingredient(name: "Rice", category: .grain), quantity: 500, unit: .grams, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Eggs", category: .other), quantity: 2, unit: .pieces, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Onion", category: .produce), quantity: 1, unit: .pieces, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Carrot", category: .produce), quantity: 2, unit: .pieces, role: .optional),
                    RecipeIngredient(ingredient: Ingredient(name: "Soy Sauce", category: .spice), quantity: 30, unit: .milliliters, role: .essential),
                ],
                instructions: [
                    "Cook the rice and let it cool (day-old rice works best).",
                    "Scramble the eggs and set aside.",
                    "Stir-fry onion and carrot until softened.",
                    "Add the rice, egg, and soy sauce, tossing until combined.",
                ],
                symbolName: "leaf.fill"
            ),
            Recipe(
                title: "Classic Cheese Omelette",
                summary: "A simple three-egg omelette with melted cheddar.",
                servings: 1,
                ingredients: [
                    RecipeIngredient(ingredient: Ingredient(name: "Eggs", category: .other), quantity: 3, unit: .pieces, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Milk", category: .dairy), quantity: 30, unit: .milliliters, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Cheddar", category: .dairy), quantity: 50, unit: .grams, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Butter", category: .dairy), quantity: 10, unit: .grams, role: .optional),
                ],
                instructions: [
                    "Whisk the eggs with the milk.",
                    "Melt butter in a nonstick pan over medium heat.",
                    "Pour in the eggs and cook until nearly set.",
                    "Sprinkle cheddar over half, fold, and serve.",
                ],
                symbolName: "circle.grid.2x2.fill"
            ),
            Recipe(
                title: "Beef Tacos",
                summary: "Weeknight tacos with a quick spiced beef filling.",
                servings: 4,
                ingredients: [
                    RecipeIngredient(ingredient: Ingredient(name: "Ground Beef", category: .meat), quantity: 400, unit: .grams, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Tortilla", category: .grain), quantity: 8, unit: .pieces, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Cheddar", category: .dairy), quantity: 100, unit: .grams, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Onion", category: .produce), quantity: 1, unit: .pieces, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Lettuce", category: .produce), quantity: 50, unit: .grams, role: .optional),
                    RecipeIngredient(ingredient: Ingredient(name: "Salsa", category: .spice), quantity: 50, unit: .milliliters, role: .optional),
                ],
                instructions: [
                    "Brown the ground beef with diced onion and taco seasoning.",
                    "Warm the tortillas.",
                    "Fill each tortilla with beef and cheddar.",
                    "Top with lettuce and salsa if you have them.",
                ],
                symbolName: "flame.fill"
            ),
            Recipe(
                title: "Tomato Soup",
                summary: "A comforting blended tomato soup.",
                servings: 4,
                ingredients: [
                    RecipeIngredient(ingredient: Ingredient(name: "Tomato", category: .produce), quantity: 500, unit: .grams, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Onion", category: .produce), quantity: 1, unit: .pieces, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Vegetable Stock", category: .other), quantity: 500, unit: .milliliters, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Cream", category: .dairy), quantity: 50, unit: .milliliters, role: .optional),
                    RecipeIngredient(ingredient: Ingredient(name: "Basil", category: .spice), quantity: 5, unit: .grams, role: .optional),
                ],
                instructions: [
                    "Sauté the onion until soft.",
                    "Add the tomatoes and stock, then simmer for 20 minutes.",
                    "Blend until smooth.",
                    "Stir in cream and basil to finish, if using.",
                ],
                symbolName: "drop.fill"
            ),
            Recipe(
                title: "Banana Pancakes",
                summary: "Fluffy pancakes studded with ripe banana.",
                servings: 2,
                ingredients: [
                    RecipeIngredient(ingredient: Ingredient(name: "Flour", category: .grain), quantity: 200, unit: .grams, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Milk", category: .dairy), quantity: 250, unit: .milliliters, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Eggs", category: .other), quantity: 1, unit: .pieces, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Banana", category: .produce), quantity: 2, unit: .pieces, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Butter", category: .dairy), quantity: 20, unit: .grams, role: .optional),
                ],
                instructions: [
                    "Whisk the flour, milk, and egg into a smooth batter.",
                    "Mash one banana into the batter; slice the other for topping.",
                    "Cook spoonfuls of batter on a buttered griddle until golden.",
                    "Top with banana slices and butter.",
                ],
                symbolName: "square.grid.3x3.fill"
            ),
            Recipe(
                title: "Grilled Cheese Sandwich",
                summary: "A buttery, crisp classic.",
                servings: 1,
                ingredients: [
                    RecipeIngredient(ingredient: Ingredient(name: "Bread", category: .grain), quantity: 2, unit: .pieces, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Cheddar", category: .dairy), quantity: 100, unit: .grams, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Butter", category: .dairy), quantity: 20, unit: .grams, role: .essential),
                ],
                instructions: [
                    "Butter one side of each bread slice.",
                    "Layer cheddar between the slices, buttered sides out.",
                    "Grill in a pan over medium heat until golden on both sides.",
                ],
                symbolName: "square.stack.fill"
            ),
            Recipe(
                title: "Chicken Caesar Salad",
                summary: "A hearty salad with seared chicken and parmesan.",
                servings: 2,
                ingredients: [
                    RecipeIngredient(ingredient: Ingredient(name: "Lettuce", category: .produce), quantity: 200, unit: .grams, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Chicken Breast", category: .meat), quantity: 200, unit: .grams, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Parmesan", category: .dairy), quantity: 30, unit: .grams, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Caesar Dressing", category: .spice), quantity: 30, unit: .milliliters, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Croutons", category: .grain), quantity: 50, unit: .grams, role: .optional),
                ],
                instructions: [
                    "Sear the chicken breast and slice once rested.",
                    "Toss the lettuce with the dressing.",
                    "Top with chicken, parmesan, and croutons if you have them.",
                ],
                symbolName: "leaf.fill"
            ),
            Recipe(
                title: "Rice and Beans",
                summary: "A simple, filling one-pot staple.",
                servings: 4,
                ingredients: [
                    RecipeIngredient(ingredient: Ingredient(name: "Rice", category: .grain), quantity: 300, unit: .grams, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Black Beans", category: .other), quantity: 400, unit: .grams, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Onion", category: .produce), quantity: 1, unit: .pieces, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Garlic", category: .produce), quantity: 2, unit: .pieces, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Cumin", category: .spice), quantity: 5, unit: .grams, role: .optional),
                ],
                instructions: [
                    "Cook the rice according to package directions.",
                    "Sauté onion and garlic until fragrant.",
                    "Add the beans and cumin, simmering until heated through.",
                    "Serve the beans over rice.",
                ],
                symbolName: "square.grid.3x3.fill"
            ),
            Recipe(
                title: "Greek Yogurt Parfait",
                summary: "A no-cook breakfast layered with fruit and granola.",
                servings: 1,
                ingredients: [
                    RecipeIngredient(ingredient: Ingredient(name: "Greek Yogurt", category: .dairy), quantity: 300, unit: .grams, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Granola", category: .grain), quantity: 100, unit: .grams, role: .essential),
                    RecipeIngredient(ingredient: Ingredient(name: "Honey", category: .spice), quantity: 20, unit: .milliliters, role: .optional),
                    RecipeIngredient(ingredient: Ingredient(name: "Berries", category: .produce), quantity: 100, unit: .grams, role: .optional),
                ],
                instructions: [
                    "Layer yogurt and granola in a glass.",
                    "Top with berries and a drizzle of honey if you have them.",
                ],
                symbolName: "drop.fill"
            ),
        ]
    }
}
