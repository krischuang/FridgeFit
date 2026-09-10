//
//  SubstitutionRequest.swift
//  FridgeFit
//

import Foundation

/// One pantry item, reduced to just what a substitution provider needs to
/// know - no ids, no Firebase user info.
struct PantryIngredientSummary: Equatable, Codable {
    let name: String
    let quantity: Double
    let unit: MeasurementUnit
}

/// Everything needed to ask "what can I use instead of this ingredient?" -
/// deliberately scoped to recipe/ingredient/pantry facts, nothing about
/// the signed-in user beyond what's already anonymous domain data.
struct SubstitutionRequest: Equatable {
    let recipeID: UUID
    let recipeTitle: String
    let targetIngredientName: String
    let requiredQuantity: Double
    let requiredUnit: MeasurementUnit
    let role: IngredientRole
    let pantryIngredients: [PantryIngredientSummary]
    let feasibilityStatus: RecipeFeasibilityStatus
    /// Always empty today - FridgeFit doesn't have a dietary/allergy
    /// profile yet. Present so a future phase can populate it without
    /// changing this model or the validation that reads it.
    let dietaryRestrictions: [String]

    init(
        recipeID: UUID,
        recipeTitle: String,
        targetIngredientName: String,
        requiredQuantity: Double,
        requiredUnit: MeasurementUnit,
        role: IngredientRole,
        pantryIngredients: [PantryIngredientSummary],
        feasibilityStatus: RecipeFeasibilityStatus,
        dietaryRestrictions: [String] = []
    ) {
        self.recipeID = recipeID
        self.recipeTitle = recipeTitle
        self.targetIngredientName = targetIngredientName
        self.requiredQuantity = requiredQuantity
        self.requiredUnit = requiredUnit
        self.role = role
        self.pantryIngredients = pantryIngredients
        self.feasibilityStatus = feasibilityStatus
        self.dietaryRestrictions = dietaryRestrictions
    }
}
