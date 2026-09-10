//
//  RecipeFeasibilityResult.swift
//  FridgeFit
//

import Foundation

/// One recipe ingredient after being checked against the pantry: what's
/// needed, what's on hand (in the pantry's own unit), and the resulting
/// availability.
struct RecipeIngredientEvaluation: Identifiable, Hashable {
    var id: UUID { recipeIngredient.id }
    let recipeIngredient: RecipeIngredient
    /// Quantity on hand, in the pantry's own unit. `nil` if the ingredient
    /// isn't in the pantry at all.
    let pantryQuantity: Double?
    /// The pantry's unit for this ingredient - may differ from the
    /// recipe's unit.
    let pantryUnit: MeasurementUnit?
    let availability: IngredientAvailability

    var ingredient: Ingredient { recipeIngredient.ingredient }
    var role: IngredientRole { recipeIngredient.role }

    /// "500 g" style formatting of what's on hand. `nil` if nothing is on
    /// hand.
    var formattedPantryQuantity: String? {
        guard let pantryQuantity, let pantryUnit else { return nil }
        return pantryUnit.formatted(pantryQuantity)
    }

    /// How much more is needed, in the recipe's own unit.
    ///
    /// `nil` when there's nothing meaningful to report: already available,
    /// or the pantry amount couldn't be safely converted to compare
    /// (`quantityUnverified`) - reporting a shortfall there would imply a
    /// precision this phase doesn't have.
    var missingQuantity: Double? {
        switch availability {
        case .available, .quantityUnverified:
            return nil
        case .missing:
            return recipeIngredient.quantity
        case .insufficient:
            guard
                let pantryQuantity, let pantryUnit,
                let converted = MeasurementUnit.convert(quantity: pantryQuantity, from: pantryUnit, to: recipeIngredient.unit)
            else {
                return nil
            }
            return max(recipeIngredient.quantity - converted, 0)
        }
    }
}

/// The result of comparing a `Recipe` against the pantry - FridgeFit's
/// answer to "can I make this?".
///
/// One model instead of scattered booleans, so the list row, the detail
/// screen, and the tests all read the same verdict.
struct RecipeFeasibilityResult {
    let recipe: Recipe
    /// Every ingredient the recipe calls for, already compared against the
    /// pantry, in the recipe's own order.
    let evaluatedIngredients: [RecipeIngredientEvaluation]
    let status: RecipeFeasibilityStatus

    var availableIngredients: [RecipeIngredientEvaluation] {
        evaluatedIngredients.filter { $0.availability == .available }
    }

    /// Essential ingredients that aren't in the pantry at all.
    var missingIngredients: [RecipeIngredientEvaluation] {
        evaluatedIngredients.filter { $0.role == .essential && $0.availability == .missing }
    }

    /// Essential ingredients that are in the pantry but short (or whose
    /// amount couldn't be safely verified).
    var insufficientIngredients: [RecipeIngredientEvaluation] {
        evaluatedIngredients.filter { $0.role == .essential && ($0.availability == .insufficient || $0.availability == .quantityUnverified) }
    }

    /// Optional ingredients that aren't fully available - never affects
    /// `status` or `canMakeRecipe`.
    var optionalMissingIngredients: [RecipeIngredientEvaluation] {
        evaluatedIngredients.filter { $0.role == .optional && $0.availability != .available }
    }

    private var essentialIngredients: [RecipeIngredientEvaluation] {
        evaluatedIngredients.filter { $0.role == .essential }
    }

    var totalRequiredCount: Int { essentialIngredients.count }
    var matchedCount: Int { essentialIngredients.filter { $0.availability == .available }.count }

    /// Percentage of essential ingredients available, 0-100. A recipe with
    /// no essential ingredients is trivially 100% covered.
    var coveragePercentage: Double {
        guard totalRequiredCount > 0 else { return 100 }
        return (Double(matchedCount) / Double(totalRequiredCount)) * 100
    }

    var canMakeRecipe: Bool { status == .makeable }
}
