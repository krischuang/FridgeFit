//
//  RecipeRecommendation.swift
//  FridgeFit
//

import Foundation

/// One recipe, selected and ordered for the user's current cooking context.
///
/// Position in the returned array *is* the rank; there is no score field,
/// because the ordering comes from a comparator over explainable facts
/// rather than from a weighted number nobody could justify to a user.
nonisolated struct RecipeRecommendation: Identifiable, Equatable {
    let suitability: RecipeSuitability
    let rankingReasons: [RecommendationReason]

    var id: UUID { suitability.recipe.id }
    var recipe: Recipe { suitability.recipe }
    var readiness: RecipeReadiness { suitability.readiness }
}

/// A fact that contributed to a recipe's ranking, in a form that can be
/// shown to the user.
///
/// ## Every case must be earned
///
/// A reason is only attached when the underlying data supports it, and
/// each one maps to something verified rather than assumed:
///
/// - `readyToCook` requires `RecipeFeasibilityStatus.makeable`, which
///   means quantities were converted and compared - not that a name
///   matched.
/// - `usesIngredientExpiringSoon` requires a pantry item with a real
///   expiry date whose `ExpiryState.shouldPrioritise` is true and which is
///   not already expired.
/// - `fitsCookingTime` / `fitsDifficulty` require the recipe to actually
///   state a time or difficulty. An unstated value never earns the reason.
/// - `matchesDietaryRestrictions` requires `DietaryCompliance.satisfied`,
///   so it can never appear for a recipe whose labels are unknown.
///
/// There is deliberately no "balanced nutrition" case. The source branch
/// had one backed by a hand-assigned `NutritionBalance` enum; main has no
/// nutrition data for its recipes, and inventing a balance rating is a
/// health claim this app has no basis for.
nonisolated enum RecommendationReason: String, Equatable, Hashable, CaseIterable, Sendable {
    case readyToCook
    case usesIngredientExpiringSoon
    case minimalShopping
    case matchesCuisinePreference
    case matchesTastePreference
    case fitsCookingTime
    case fitsDifficulty
    case matchesDietaryRestrictions
    case strongPantryMatch

    var displayText: String {
        switch self {
        case .readyToCook:
            return "Ready with your pantry"
        case .usesIngredientExpiringSoon:
            return "Uses an ingredient expiring soon"
        case .minimalShopping:
            return "Needs only one more ingredient"
        case .matchesCuisinePreference:
            return "Matches your cuisine preference"
        case .matchesTastePreference:
            return "Matches your taste preference"
        case .fitsCookingTime:
            return "Fits your available time"
        case .fitsDifficulty:
            return "Fits your cooking confidence"
        case .matchesDietaryRestrictions:
            return "Meets your dietary requirements"
        case .strongPantryMatch:
            return "Uses many ingredients you have"
        }
    }

    var symbolName: String {
        switch self {
        case .readyToCook: return "checkmark.circle.fill"
        case .usesIngredientExpiringSoon: return "clock.badge.exclamationmark.fill"
        case .minimalShopping: return "cart.fill"
        case .matchesCuisinePreference: return "globe"
        case .matchesTastePreference: return "heart.fill"
        case .fitsCookingTime: return "timer"
        case .fitsDifficulty: return "dial.low.fill"
        case .matchesDietaryRestrictions: return "leaf.fill"
        case .strongPantryMatch: return "cabinet.fill"
        }
    }
}
