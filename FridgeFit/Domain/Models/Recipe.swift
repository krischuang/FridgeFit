//
//  Recipe.swift
//  FridgeFit
//

import Foundation

/// A dish the user might want to make: a title, its ingredients, and how
/// to cook it.
///
/// Recipe stays simple - quantities, units, and role all live on
/// `RecipeIngredient` so feasibility logic doesn't creep in here.
///
/// ## The recommendation metadata
///
/// `cuisine`, `tastePreferences`, `dietaryLabels`,
/// `totalCookingTimeInMinutes` and `difficulty` were added for the
/// context-aware recommendation feature. **Every one of them is
/// optional**, for the same load-bearing reason the kitchen fields on
/// `PantryItem` are: a recipe encoded before they existed decodes with
/// `nil` in each one, and every existing initializer call site still
/// compiles unchanged because each new parameter has a default.
///
/// Nothing in the existing recipe flow reads them.
/// `EvaluateRecipeFeasibilityUseCase`, `RecipeViewModel`, `RecipeListView`
/// and `RecipeDetailView` are untouched by this addition - feasibility is
/// still computed only from `ingredients`.
///
/// ## Why `nil` is not "no"
///
/// An absent value means *unstated*, never *zero* and never *excluded*.
/// The recommendation engine treats the two kinds of absence differently:
///
/// - Unstated time or difficulty is a non-safety preference, so the recipe
///   is still offered and simply earns no ranking credit. Filtering it out
///   would empty the list for any user who set a time limit.
/// - Unstated `dietaryLabels` is a safety question, so it is reported as
///   `DietaryCompliance.unknown` and the recipe is withheld whenever the
///   user has selected a restriction. "We were never told" is not
///   evidence of compliance.
///
/// There is deliberately no nutrition field. The branch this feature came
/// from carried a hand-assigned `NutritionBalance` per recipe; main has no
/// nutrition data for any recipe, and a "balanced meal" badge with nothing
/// behind it is a health claim the app cannot support.
struct Recipe: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var summary: String
    /// `nil` when the source doesn't specify a serving count.
    var servings: Int?
    var ingredients: [RecipeIngredient]
    /// One entry per step, in cooking order.
    var instructions: [String]
    /// SF Symbol name for the recipe list/detail icon. Optional since not
    /// every source will provide one - no photo pipeline in this phase.
    var symbolName: String?

    // MARK: - Recommendation metadata (all optional, all absent on legacy recipes)

    /// The recipe's broad cuisine style. `nil` when unstated; ranking then
    /// skips the cuisine comparison for this recipe rather than treating it
    /// as a mismatch.
    var cuisine: Cuisine?
    /// The taste characteristics this dish leans on. `nil` when unstated.
    var tastePreferences: Set<TastePreference>?
    /// The dietary restrictions this recipe is *known* to satisfy.
    ///
    /// `nil` means no one has assessed it - read through
    /// `dietaryCompliance(with:)`, which reports that as
    /// `DietaryCompliance.unknown` rather than as compliance. An empty set
    /// is different again: it means assessed, and satisfies none.
    var dietaryLabels: Set<DietaryRestriction>?
    /// Total hands-on plus cooking time. `nil` when unstated.
    var totalCookingTimeInMinutes: Int?
    /// How demanding the recipe is. `nil` when unstated.
    var difficulty: CookingDifficulty?

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        servings: Int? = nil,
        ingredients: [RecipeIngredient],
        instructions: [String],
        symbolName: String? = nil,
        cuisine: Cuisine? = nil,
        tastePreferences: Set<TastePreference>? = nil,
        dietaryLabels: Set<DietaryRestriction>? = nil,
        totalCookingTimeInMinutes: Int? = nil,
        difficulty: CookingDifficulty? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.servings = servings
        self.ingredients = ingredients
        self.instructions = instructions
        self.symbolName = symbolName
        self.cuisine = cuisine
        self.tastePreferences = tastePreferences
        self.dietaryLabels = dietaryLabels
        self.totalCookingTimeInMinutes = totalCookingTimeInMinutes
        self.difficulty = difficulty
    }

    // MARK: - Metadata readings

    /// Whether this recipe states enough for the ranking rules to say
    /// anything about it beyond its pantry coverage.
    ///
    /// Used only for the "limited information" note in the UI; it never
    /// excludes a recipe.
    var hasRecommendationMetadata: Bool {
        cuisine != nil
            || tastePreferences?.isEmpty == false
            || dietaryLabels != nil
            || totalCookingTimeInMinutes != nil
            || difficulty != nil
    }

    /// Whether the recipe's stated time fits within `limit`.
    ///
    /// `nil` when the recipe doesn't state a time - the caller decides what
    /// to do with "unknown", and the two call sites decide differently:
    /// filtering lets it through, ranking gives it no credit.
    func fitsCookingTime(within limit: CookingTimeLimit) -> Bool? {
        guard let totalCookingTimeInMinutes else { return nil }
        return totalCookingTimeInMinutes <= limit.rawValue
    }

    /// Whether the recipe's stated difficulty is at or below `maximum`.
    ///
    /// `nil` when the recipe doesn't state a difficulty.
    func fitsDifficulty(atMost maximum: CookingDifficulty) -> Bool? {
        guard let difficulty else { return nil }
        return difficulty <= maximum
    }

    /// Whether the recipe's stated cuisine is one the user prefers.
    ///
    /// `false` when either side is unstated or empty - an unstated cuisine
    /// earns no preference credit, but is never penalised beyond that.
    func matchesCuisine(in preferred: Set<Cuisine>) -> Bool {
        guard let cuisine, !preferred.isEmpty else { return false }
        return preferred.contains(cuisine)
    }

    /// Whether any of the recipe's stated tastes is one the user prefers.
    func matchesTaste(in preferred: Set<TastePreference>) -> Bool {
        guard let tastePreferences, !preferred.isEmpty else { return false }
        return !preferred.isDisjoint(with: tastePreferences)
    }
}
