//
//  SavedRecipeEntity.swift
//  FridgeFit
//

import Foundation
import SwiftData

/// A recipe the user saved from Discover, stored on the device.
///
/// Saving copies everything the Recipes tab needs - title, summary, method
/// and ingredient lines - into the user's own store, so opening, ranking or
/// cooking a saved recipe never calls the recipe provider again.
///
/// ## Identity
///
/// `recipeID` is derived from the provider's recipe id
/// (`SaveOnlineRecipeUseCase.savedRecipeID`), so saving the same recipe
/// twice updates one row instead of adding a duplicate. It is deliberately
/// **not** `@Attribute(.unique)`: two accounts on one device may both save
/// the same recipe, and each must keep their own copy. Uniqueness is per
/// `(ownerID, recipeID)` and is enforced by `SwiftDataSavedRecipeStore`.
///
/// ## Why ingredient lines are their own model
///
/// They have their own identity (`RecipeIngredient.id`, which the
/// substitution screen keys its state by) and their own role and unit, so
/// they are rows, not an opaque blob. `position` keeps recipe order, which
/// a SwiftData to-many relationship does not preserve on its own. Deleting
/// a saved recipe deletes its lines (`.cascade`).
@Model
final class SavedRecipeEntity {
    var recipeID: UUID
    /// Firebase Auth uid of the user who saved it.
    var ownerID: String
    /// The provider's (Spoonacular) recipe id.
    var sourceRecipeID: Int
    var title: String
    var summary: String
    var servings: Int?
    var instructions: [String]
    var symbolName: String?
    var totalCookingTimeInMinutes: Int?

    // Recommendation metadata, as raw values. All optional, mirroring `Recipe`.
    var cuisine: String?
    var tastePreferences: [String]?
    var dietaryLabels: [String]?
    var difficulty: Int?

    var savedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \SavedRecipeIngredientEntity.recipe)
    var ingredients: [SavedRecipeIngredientEntity] = []

    init(
        recipeID: UUID,
        ownerID: String,
        sourceRecipeID: Int,
        title: String,
        summary: String,
        servings: Int? = nil,
        instructions: [String],
        symbolName: String? = nil,
        totalCookingTimeInMinutes: Int? = nil,
        cuisine: String? = nil,
        tastePreferences: [String]? = nil,
        dietaryLabels: [String]? = nil,
        difficulty: Int? = nil,
        savedAt: Date
    ) {
        self.recipeID = recipeID
        self.ownerID = ownerID
        self.sourceRecipeID = sourceRecipeID
        self.title = title
        self.summary = summary
        self.servings = servings
        self.instructions = instructions
        self.symbolName = symbolName
        self.totalCookingTimeInMinutes = totalCookingTimeInMinutes
        self.cuisine = cuisine
        self.tastePreferences = tastePreferences
        self.dietaryLabels = dietaryLabels
        self.difficulty = difficulty
        self.savedAt = savedAt
    }
}

/// One ingredient line of a `SavedRecipeEntity`.
@Model
final class SavedRecipeIngredientEntity {
    /// `RecipeIngredient.id`, kept stable across loads.
    var lineID: UUID
    /// Order within the recipe.
    var position: Int
    /// `Ingredient.id`.
    var ingredientID: UUID
    var name: String
    var category: String
    var quantity: Double
    var unit: String
    var role: String
    var recipe: SavedRecipeEntity?

    init(
        lineID: UUID,
        position: Int,
        ingredientID: UUID,
        name: String,
        category: String,
        quantity: Double,
        unit: String,
        role: String
    ) {
        self.lineID = lineID
        self.position = position
        self.ingredientID = ingredientID
        self.name = name
        self.category = category
        self.quantity = quantity
        self.unit = unit
        self.role = role
    }
}
