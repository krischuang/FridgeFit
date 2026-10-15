//
//  SaveOnlineRecipeUseCase.swift
//  FridgeFit
//

import Foundation

/// Saves a Discover recipe to the user's Recipes page by converting it into
/// an ordinary `Recipe`.
///
/// Once saved, the recipe is evaluated by `EvaluateRecipeFeasibilityUseCase`
/// like any bundled recipe - the provider's own "used / missed" verdict is
/// not carried over, because the Recipes page must agree with the real
/// pantry, quantities included. This is the boundary at which loose online
/// data becomes a first-class `Recipe`, and it is the only one.
///
/// ## Ingredient conversion rules
///
/// - The id is derived from the provider id (`savedRecipeID(forOnlineRecipeID:)`),
///   so saving the same recipe twice overwrites rather than duplicates.
/// - A line with a known unit keeps it and is **essential**.
/// - Seasoning-style lines with no real amount ("a pinch", "to taste",
///   "servings", amount 0) become **optional**: they can't be checked, and
///   shouldn't make a dish look unmakeable.
/// - Any other unrecognised unit ("cloves", "large", "can"...) becomes
///   pieces and stays essential, so an important ingredient is never
///   silently dropped. If the pantry stores it in another unit,
///   `MeasurementUnit.convert` returns `nil` and the feasibility engine
///   reports `.quantityUnverified` rather than `.available` - the recipe
///   fails closed instead of claiming a quantity it never checked.
/// - Repeated ingredient names keep only the first line, since feasibility
///   matches by name.
/// - A recipe with no usable ingredient lines can't be saved.
///
/// ## Which recommendation metadata is carried over, and which is not
///
/// `totalCookingTimeInMinutes` is populated from the provider's
/// `readyInMinutes`. It is a stated duration, and `main` uses a stated time
/// only to grant ranking credit or pass a time filter - never to make a
/// safety claim - so carrying it across lets a saved recipe be ranked on
/// the same footing as a bundled one.
///
/// Everything else is deliberately left `nil`:
///
/// - `dietaryLabels` stays `nil`, so `dietaryCompliance(with:)` reports
///   `.unknown` and the recipe is withheld whenever the user has selected a
///   restriction. The provider's `diets` array is a provider claim, and
///   `DietaryCompliance` is explicit that a label FridgeFit did not
///   establish is not evidence of compliance. Unknown stays unknown.
/// - `cuisine` stays `nil`. `Cuisine` is a closed five-case vocabulary;
///   mapping arbitrary provider cuisine strings onto it would be guessing,
///   and an unstated cuisine costs a recipe nothing but ranking credit.
/// - `difficulty` stays `nil` - the provider reports nothing comparable.
/// - `tastePreferences` stays `nil` for the same reason as cuisine.
nonisolated struct SaveOnlineRecipeUseCase {
    let repository: SavedRecipeRepository

    @discardableResult
    func execute(_ onlineRecipe: OnlineRecipe) async throws -> Recipe {
        let recipe = try Self.recipe(from: onlineRecipe)
        do {
            try await repository.save(recipe, sourceRecipeID: onlineRecipe.id)
        } catch let error as SaveOnlineRecipeError {
            throw error
        } catch {
            throw SaveOnlineRecipeError.saveFailed
        }
        return recipe
    }

    // MARK: - Conversion

    static let summaryCharacterLimit = 400

    private static let seasoningWords: Set<String> = [
        "pinch", "pinches", "dash", "dashes", "to taste", "serving", "servings",
        "sprig", "sprigs", "handful", "handfuls",
    ]

    /// A stable `Recipe` id for a provider recipe id.
    ///
    /// Deterministic, so saving the same recipe twice is idempotent and a
    /// session's feedback keyed on `Recipe.id` keeps referring to the same
    /// dish. Shaped as a v4 UUID in a fixed namespace, which cannot collide
    /// with the random UUIDs bundled recipes use.
    static func savedRecipeID(forOnlineRecipeID id: Int) -> UUID {
        let bits = UInt64(bitPattern: Int64(id)) & 0xFFFF_FFFF_FFFF
        return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012llx", bits))!
    }

    static func recipe(from online: OnlineRecipe) throws -> Recipe {
        var seenNames = Set<String>()
        let ingredients: [RecipeIngredient] = online.ingredients.compactMap { line in
            let name = OnlineIngredientName.normalized(line.name)
            guard !name.isEmpty, seenNames.insert(name.lowercased()).inserted else { return nil }
            let (quantity, unit, role) = quantityUnitAndRole(for: line)
            return RecipeIngredient(
                ingredient: Ingredient(name: OnlineIngredientName.displayName(name), category: .other),
                quantity: quantity,
                unit: unit,
                role: role
            )
        }
        guard !ingredients.isEmpty else { throw SaveOnlineRecipeError.noUsableIngredients }

        let instructions: [String]
        if !online.steps.isEmpty {
            instructions = online.steps
        } else if let source = online.sourceURL {
            instructions = ["No step-by-step method was provided. See the original recipe: \(source.absoluteString)"]
        } else {
            instructions = ["No step-by-step method was provided for this recipe."]
        }

        return Recipe(
            id: savedRecipeID(forOnlineRecipeID: online.id),
            title: online.title,
            summary: summary(for: online),
            servings: online.servings,
            ingredients: ingredients,
            instructions: instructions,
            symbolName: "globe",
            totalCookingTimeInMinutes: online.readyInMinutes
        )
    }

    static func quantityUnitAndRole(for line: OnlineRecipeIngredient) -> (Double, MeasurementUnit, IngredientRole) {
        let rawUnit = line.originalUnit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let amount = max(line.amount, 0)

        if line.quantityIsUncertain || amount == 0 || seasoningWords.contains(rawUnit) {
            return (amount > 0 ? amount : 1, line.unit ?? .pieces, .optional)
        }
        return (amount, line.unit ?? .pieces, .essential)
    }

    private static func summary(for online: OnlineRecipe) -> String {
        var text = (online.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > summaryCharacterLimit {
            text = String(text.prefix(summaryCharacterLimit)).trimmingCharacters(in: .whitespaces) + "…"
        }
        let source = online.sourceName.map { "From \($0), via Spoonacular." } ?? "Saved from Discover, via Spoonacular."
        return text.isEmpty ? source : "\(text)\n\n\(source)"
    }
}
