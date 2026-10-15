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
    /// The bundled dataset, including the recommendation metadata the
    /// context-aware ranking reads.
    ///
    /// ## How the metadata was assigned
    ///
    /// `cuisine`, `tastePreferences`, `totalCookingTimeInMinutes` and
    /// `difficulty` are editorial values for this curated dataset, derived
    /// from each recipe's own ingredients, steps and serving count. They
    /// are ordinary recipe-card information, and none of them is a safety
    /// claim - the worst a wrong one can do is rank a dish badly.
    ///
    /// `dietaryLabels` is held to a stricter rule, because it *is* a safety
    /// claim. Only the restrictions whose
    /// `DietaryRestriction.assessmentBasis` is `.composition` are ever
    /// listed, and one is listed only when every ingredient the recipe
    /// names - optional ones included - establishes it:
    ///
    /// - `vegetarian` / `vegan` / `dairyFree` follow from the stated
    ///   ingredients, counting optional ingredients against the label. The
    ///   tomato soup lists cream as optional, so it is not labelled
    ///   `dairyFree`; a label that only holds if you skip an ingredient is
    ///   not a label.
    /// - `glutenFree` and `nutFree` are listed on **no** recipe, because
    ///   this dataset cannot establish either. Twenty of its thirty-two
    ///   ingredients are processed or composite products recorded by
    ///   generic name only - "Cheddar", "Butter", "Cumin", "Vegetable
    ///   Stock", "Granola", "Caesar Dressing" - with no brand, no
    ///   processing information and no allergen declaration. Whether any
    ///   of them contains gluten or nuts is a property of the specific
    ///   product bought, not of the word. For coeliac disease and nut
    ///   allergy a trace is the whole problem, so "no gluten-bearing
    ///   ingredient is named" is not the same claim as "gluten-free" and
    ///   must not be published as if it were.
    ///
    ///   An earlier revision of this dataset did label the cheese omelette
    ///   and the rice and beans `glutenFree` on the grounds that no grain
    ///   appeared in them. That was withdrawn: it applied a weaker
    ///   standard to gluten than the one already applied to nuts, and the
    ///   cross-contamination argument that rules out a nut-free claim
    ///   rules out a gluten-free claim for exactly the same reason.
    ///
    /// An empty set therefore means *assessed against every restriction
    /// FridgeFit can assess, and satisfies none of them* - a different
    /// fact from `nil`, meaning never assessed. See `Recipe.dietaryLabels`
    /// and `DietaryCompliance`.
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
                symbolName: "fork.knife",
                cuisine: .italian,
                tastePreferences: [.savoury, .hearty],
                // Chicken, cream and wheat pasta: satisfies none of the
                // restrictions modelled here.
                dietaryLabels: [],
                totalCookingTimeInMinutes: 30,
                difficulty: .easy
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
                symbolName: "leaf.fill",
                cuisine: .asian,
                tastePreferences: [.savoury],
                // Egg rules out vegan; no dairy anywhere. Not labelled
                // gluten free - soy sauce commonly contains wheat.
                dietaryLabels: [.vegetarian, .dairyFree],
                totalCookingTimeInMinutes: 25,
                difficulty: .easy
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
                symbolName: "circle.grid.2x2.fill",
                cuisine: .comfortFood,
                tastePreferences: [.savoury, .mild],
                // Milk, cheddar and butter rule out vegan and dairy free.
                // No gluten-bearing ingredient is named, but cheddar and
                // butter are processed products with no provenance here, so
                // no gluten-free claim is made.
                dietaryLabels: [.vegetarian],
                totalCookingTimeInMinutes: 10,
                difficulty: .easy
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
                symbolName: "flame.fill",
                cuisine: .mexican,
                tastePreferences: [.savoury, .spicy, .hearty],
                // Beef, cheddar and wheat tortillas.
                dietaryLabels: [],
                totalCookingTimeInMinutes: 25,
                difficulty: .easy
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
                symbolName: "drop.fill",
                cuisine: .mediterranean,
                tastePreferences: [.fresh, .mild],
                // Cream is optional, but a label that only holds if you
                // skip an ingredient is not a label - so no dairy free and
                // no vegan. Stock provenance is unknown, so no gluten free.
                dietaryLabels: [.vegetarian],
                totalCookingTimeInMinutes: 35,
                difficulty: .easy
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
                symbolName: "square.grid.3x3.fill",
                cuisine: .comfortFood,
                tastePreferences: [.mild],
                // Wheat flour, milk, egg and butter.
                dietaryLabels: [.vegetarian],
                totalCookingTimeInMinutes: 25,
                difficulty: .moderate
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
                symbolName: "square.stack.fill",
                cuisine: .comfortFood,
                tastePreferences: [.savoury, .mild, .hearty],
                // Wheat bread, cheddar and butter.
                dietaryLabels: [.vegetarian],
                totalCookingTimeInMinutes: 10,
                difficulty: .easy
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
                symbolName: "leaf.fill",
                cuisine: .mediterranean,
                tastePreferences: [.fresh, .savoury],
                // Chicken, parmesan, and dressing that conventionally
                // contains anchovy and egg.
                dietaryLabels: [],
                totalCookingTimeInMinutes: 20,
                difficulty: .easy
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
                symbolName: "square.grid.3x3.fill",
                cuisine: .mexican,
                tastePreferences: [.hearty, .savoury],
                // Rice, beans and aromatics: no animal product at all,
                // optional cumin included. Not labelled gluten free -
                // canned beans and ground spice blends are processed
                // products whose gluten status this dataset cannot
                // establish.
                dietaryLabels: [.vegetarian, .vegan, .dairyFree],
                totalCookingTimeInMinutes: 30,
                difficulty: .easy
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
                symbolName: "drop.fill",
                cuisine: .mediterranean,
                tastePreferences: [.fresh, .mild],
                // Yogurt rules out vegan and dairy free; granola is
                // oat/wheat based, so no gluten free.
                dietaryLabels: [.vegetarian],
                totalCookingTimeInMinutes: 5,
                difficulty: .easy
            ),
        ]
    }
}
