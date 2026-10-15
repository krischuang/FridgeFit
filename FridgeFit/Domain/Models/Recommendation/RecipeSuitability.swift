//
//  RecipeSuitability.swift
//  FridgeFit
//

import Foundation

/// How close a recipe is to being practically cookable right now.
///
/// ## Relationship to `RecipeFeasibilityStatus`
///
/// This is a *reading* of `RecipeFeasibilityStatus`, not a second opinion
/// about it. `EvaluateRecipeFeasibilityUseCase` remains the only thing in
/// the app that decides whether an ingredient is available, and it does so
/// by converting units and comparing amounts. `RecipeReadiness` adds one
/// distinction that feasibility deliberately folds together: whether the
/// gap is *shopping* (an essential ingredient is missing or short) or
/// *uncertainty* (the ingredient is in the pantry but its amount could not
/// be safely compared).
///
/// That distinction matters because the two need different wording. "Buy
/// one more thing" is actionable; "check how much milk you have" is not the
/// same request.
nonisolated enum RecipeReadiness: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    /// Every essential ingredient is available in a verified sufficient
    /// quantity - `RecipeFeasibilityStatus.makeable`.
    case readyToCook
    /// Nothing is missing, but at least one essential ingredient's amount
    /// could not be verified (incompatible units). Never presented as
    /// having enough.
    case almostReady
    /// One or two essential ingredients are missing or short.
    case needsOneToTwoIngredients

    var displayName: String {
        switch self {
        case .readyToCook: return "Ready to Cook"
        case .almostReady: return "Check Amounts"
        case .needsOneToTwoIngredients: return "Needs 1\u{2013}2 Ingredients"
        }
    }

    var sectionDescription: String {
        switch self {
        case .readyToCook:
            return "You have every essential ingredient in a sufficient amount."
        case .almostReady:
            return "You have every essential ingredient, but at least one amount couldn't be checked."
        case .needsOneToTwoIngredients:
            return "A small amount of additional shopping is required."
        }
    }

    var symbolName: String {
        switch self {
        case .readyToCook: return "checkmark.circle.fill"
        case .almostReady: return "questionmark.circle.fill"
        case .needsOneToTwoIngredients: return "cart.fill"
        }
    }
}

/// Why a single recipe was ruled out of a recommendation run.
///
/// An exclusion is an ordinary evaluation outcome, not a failure: one
/// unsuitable recipe must never fail the whole request. The reasons are
/// collected so `RecommendationGenerationError` can explain an empty
/// result in terms of what actually happened.
nonisolated enum RecipeExclusionReason: Equatable, Hashable, Sendable {
    /// The recipe is labelled and at least one selected restriction is not
    /// in its labels.
    case dietaryRestrictionConflict(missing: Set<DietaryRestriction>)
    /// The recipe carries no dietary labels, so compliance with the
    /// user's selected restrictions could not be established.
    case dietaryComplianceUnknown
    case cookingTimeExceedsLimit
    case difficultyExceedsLimit
    /// More than two essential ingredients are missing or short. Named for
    /// the shopping effort it implies rather than for the feasibility
    /// status, because that is what the user is being told.
    case requiresMoreThanTwoIngredients

    /// Whether this exclusion came from a preference the user can relax,
    /// as opposed to the state of their pantry.
    ///
    /// Drives the distinction between "your filters ruled everything out"
    /// and "your pantry can't make any of these yet".
    var isContextFilterExclusion: Bool {
        switch self {
        case .dietaryRestrictionConflict,
             .dietaryComplianceUnknown,
             .cookingTimeExceedsLimit,
             .difficultyExceedsLimit:
            return true
        case .requiresMoreThanTwoIngredients:
            return false
        }
    }
}

/// A pantry item this recipe would use that is close to its expiry date.
///
/// Carries the resolved `ExpiryState` rather than a bare `Bool` so the UI
/// can say "Spinach, 2 days" without recomputing urgency, and so the
/// ranking and the explanation can never disagree about which item was
/// credited.
nonisolated struct UrgentIngredientUse: Equatable, Hashable, Sendable {
    let ingredientName: String
    let urgency: ExpiryUrgency
    let daysUntilExpiry: Int?
}

/// Everything known about how well one recipe fits the current pantry and
/// context.
///
/// Holds the `RecipeFeasibilityResult` it was derived from rather than
/// copying numbers out of it, so the recommendation screen and the recipe
/// detail screen are reading the same verdict.
nonisolated struct RecipeSuitability: Equatable {
    let recipe: Recipe
    let feasibility: RecipeFeasibilityResult
    let readiness: RecipeReadiness
    /// Essential ingredients that are missing or short, in the recipe's
    /// own order. Derived from the feasibility result.
    let shoppingIngredients: [String]
    /// Essential ingredients present in the pantry whose amount could not
    /// be safely compared against the recipe's unit.
    let unverifiedIngredients: [String]
    /// Pantry items approaching expiry that this recipe would use. Empty
    /// when nothing is urgent. Already-expired food is never listed here.
    let urgentIngredients: [UrgentIngredientUse]
    /// Pantry items this recipe would use that are already past their
    /// expiry date. Surfaced as a caution, never as a reason to cook.
    let expiredIngredients: [String]
    let dietaryCompliance: DietaryCompliance

    /// Percentage of the recipe's essential ingredients that are available
    /// in a verified sufficient amount, 0-100.
    ///
    /// Taken straight from `RecipeFeasibilityResult.coveragePercentage`,
    /// which counts only `.available`. The source branch computed its own
    /// "pantry match" from name hits, which counted an ingredient the user
    /// had a trace of as a full match.
    var pantryMatchPercentage: Int {
        Int(feasibility.coveragePercentage.rounded())
    }

    /// Whether this recipe would use food approaching its expiry date.
    var usesUrgentIngredient: Bool { !urgentIngredients.isEmpty }

    /// Whether this recipe would use food that has already expired.
    var usesExpiredIngredient: Bool { !expiredIngredients.isEmpty }
}

/// The complete outcome of evaluating one recipe.
nonisolated enum RecipeSuitabilityOutcome: Equatable {
    case suitable(RecipeSuitability)
    case excluded(RecipeExclusionReason)
}
