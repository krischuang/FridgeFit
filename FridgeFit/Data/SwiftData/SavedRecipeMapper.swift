//
//  SavedRecipeMapper.swift
//  FridgeFit
//

import Foundation

/// Converts between `Recipe` and the saved-recipe SwiftData models.
///
/// Pure functions with no `ModelContext`, like `PantryItemMapper`, so the
/// field mapping can be tested on its own. Unknown raw values read back as
/// the safest option rather than failing the whole recipe: an unknown unit
/// becomes `.pieces`, an unknown role `.essential` (never silently optional),
/// and unknown metadata is dropped.
enum SavedRecipeMapper {
    static func toDomain(_ entity: SavedRecipeEntity) -> Recipe {
        let lines = entity.ingredients
            .sorted { $0.position < $1.position }
            .map { line in
                RecipeIngredient(
                    id: line.lineID,
                    ingredient: Ingredient(
                        id: line.ingredientID,
                        name: line.name,
                        category: IngredientCategory(rawValue: line.category) ?? .other
                    ),
                    quantity: line.quantity,
                    unit: MeasurementUnit(rawValue: line.unit) ?? .pieces,
                    role: IngredientRole(rawValue: line.role) ?? .essential
                )
            }

        return Recipe(
            id: entity.recipeID,
            title: entity.title,
            summary: entity.summary,
            servings: entity.servings,
            ingredients: lines,
            instructions: entity.instructions,
            symbolName: entity.symbolName,
            cuisine: entity.cuisine.flatMap(Cuisine.init(rawValue:)),
            tastePreferences: entity.tastePreferences.map { Set($0.compactMap(TastePreference.init(rawValue:))) },
            dietaryLabels: entity.dietaryLabels.map { Set($0.compactMap(DietaryRestriction.init(rawValue:))) },
            totalCookingTimeInMinutes: entity.totalCookingTimeInMinutes,
            difficulty: entity.difficulty.flatMap(CookingDifficulty.init(rawValue:))
        )
    }

    static func makeEntity(_ recipe: Recipe, ownerID: String, sourceRecipeID: Int, savedAt: Date) -> SavedRecipeEntity {
        let entity = SavedRecipeEntity(
            recipeID: recipe.id,
            ownerID: ownerID,
            sourceRecipeID: sourceRecipeID,
            title: recipe.title,
            summary: recipe.summary,
            instructions: recipe.instructions,
            savedAt: savedAt
        )
        apply(recipe, sourceRecipeID: sourceRecipeID, to: entity)
        return entity
    }

    /// Copies every recipe-level field onto `entity`. Ingredient lines are
    /// built separately (`makeLines`) because they must be inserted into the
    /// context before being attached.
    static func apply(_ recipe: Recipe, sourceRecipeID: Int, to entity: SavedRecipeEntity) {
        entity.sourceRecipeID = sourceRecipeID
        entity.title = recipe.title
        entity.summary = recipe.summary
        entity.servings = recipe.servings
        entity.instructions = recipe.instructions
        entity.symbolName = recipe.symbolName
        entity.totalCookingTimeInMinutes = recipe.totalCookingTimeInMinutes
        entity.cuisine = recipe.cuisine?.rawValue
        entity.tastePreferences = recipe.tastePreferences.map { $0.map(\.rawValue).sorted() }
        entity.dietaryLabels = recipe.dietaryLabels.map { $0.map(\.rawValue).sorted() }
        entity.difficulty = recipe.difficulty?.rawValue
    }

    static func makeLines(for recipe: Recipe) -> [SavedRecipeIngredientEntity] {
        recipe.ingredients.enumerated().map { position, line in
            SavedRecipeIngredientEntity(
                lineID: line.id,
                position: position,
                ingredientID: line.ingredient.id,
                name: line.ingredient.name,
                category: line.ingredient.category.rawValue,
                quantity: line.quantity,
                unit: line.unit.rawValue,
                role: line.role.rawValue
            )
        }
    }
}
