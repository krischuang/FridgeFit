//
//  EvaluateRecipeFeasibilityUseCase.swift
//  FridgeFit
//

import Foundation

/// Answers "can I make this?" by comparing a `Recipe`'s requirements
/// against the current user's pantry.
///
/// Reads the pantry fresh on every call via `PantryRepository`, so calling
/// it again after the pantry changes always reflects the latest state -
/// no caching, no substitutions, just a deterministic comparison.
struct EvaluateRecipeFeasibilityUseCase {
    private let pantryRepository: PantryRepository

    init(pantryRepository: PantryRepository) {
        self.pantryRepository = pantryRepository
    }

    /// Compares every ingredient `recipe` requires against the signed-in
    /// user's pantry and returns the result.
    ///
    /// Matches ingredients by normalized name (`Ingredient.matches(name:)`
    /// - trimmed, case-insensitive), the same rule Pantry itself uses, not
    /// by id: pantry items and recipe ingredients are created separately,
    /// so id equality would never match.
    func execute(recipe: Recipe) async throws -> RecipeFeasibilityResult {
        let pantryItems = try await pantryRepository.fetchAll()
        let evaluatedIngredients = recipe.ingredients.map { evaluate($0, against: pantryItems) }
        let status = Self.status(for: evaluatedIngredients)
        return RecipeFeasibilityResult(recipe: recipe, evaluatedIngredients: evaluatedIngredients, status: status)
    }

    private func evaluate(_ recipeIngredient: RecipeIngredient, against pantryItems: [PantryItem]) -> RecipeIngredientEvaluation {
        guard let pantryItem = pantryItems.first(where: { $0.ingredient.matches(name: recipeIngredient.ingredient.name) }) else {
            return RecipeIngredientEvaluation(recipeIngredient: recipeIngredient, pantryQuantity: nil, pantryUnit: nil, availability: .missing)
        }

        guard let convertedQuantity = MeasurementUnit.convert(quantity: pantryItem.quantity, from: pantryItem.unit, to: recipeIngredient.unit) else {
            // Different, unconvertible units (or an unsupported conversion
            // like cups/tbsp) - fail closed instead of guessing.
            return RecipeIngredientEvaluation(recipeIngredient: recipeIngredient, pantryQuantity: pantryItem.quantity, pantryUnit: pantryItem.unit, availability: .quantityUnverified)
        }

        let availability: IngredientAvailability = convertedQuantity >= recipeIngredient.quantity ? .available : .insufficient
        return RecipeIngredientEvaluation(recipeIngredient: recipeIngredient, pantryQuantity: pantryItem.quantity, pantryUnit: pantryItem.unit, availability: availability)
    }

    /// The one feasibility rule used everywhere - a recipe with no
    /// essential ingredients is trivially `.makeable`. Otherwise:
    ///
    /// - All essential ingredients available -> `.makeable`.
    /// - Some essential ingredients unresolved, but at least half of them
    ///   are still available -> `.almostMakeable`.
    /// - Fewer than half of the essential ingredients are available ->
    ///   `.notMakeable` ("significant required ingredients unavailable").
    ///
    /// Optional ingredients never factor in - see
    /// `RecipeFeasibilityResult.optionalMissingIngredients`.
    private static func status(for evaluatedIngredients: [RecipeIngredientEvaluation]) -> RecipeFeasibilityStatus {
        let essential = evaluatedIngredients.filter { $0.role == .essential }
        guard !essential.isEmpty else { return .makeable }

        let availableCount = essential.filter { $0.availability == .available }.count
        if availableCount == essential.count {
            return .makeable
        }

        let coverage = Double(availableCount) / Double(essential.count)
        return coverage >= 0.5 ? .almostMakeable : .notMakeable
    }
}
