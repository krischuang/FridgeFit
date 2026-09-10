//
//  RecipeIngredient.swift
//  FridgeFit
//

import Foundation

/// How important an ingredient is to a recipe.
///
/// - `essential`: required for the dish. Missing or insufficient blocks
///   the recipe.
/// - `optional`: extra/garnish. Never blocks the recipe, whatever its
///   state - see `RecipeFeasibilityResult`.
enum IngredientRole: String, Codable, CaseIterable {
    case essential
    case optional

    var displayName: String {
        switch self {
        case .essential: return "Essential"
        case .optional: return "Optional"
        }
    }
}

/// An `Ingredient` as required by one recipe: how much, what unit, and how
/// important it is to the dish.
///
/// Role and quantity live here instead of on `Ingredient` because the same
/// ingredient (e.g. cream) can be essential in one recipe and optional in
/// another.
struct RecipeIngredient: Identifiable, Hashable, Codable {
    let id: UUID
    var ingredient: Ingredient
    var quantity: Double
    var unit: MeasurementUnit
    var role: IngredientRole

    init(id: UUID = UUID(), ingredient: Ingredient, quantity: Double, unit: MeasurementUnit, role: IngredientRole) {
        self.id = id
        self.ingredient = ingredient
        self.quantity = quantity
        self.unit = unit
        self.role = role
    }

    var formattedQuantity: String { unit.formatted(quantity) }
}
