//
//  RecommendationGenerationError.swift
//  FridgeFit
//

import Foundation

/// Why FridgeFit could not produce a list of recommendations.
///
/// Distinct from a per-recipe `RecipeExclusionReason`: these end the whole
/// request. Each case carries both what happened and what the user can do
/// about it, because an empty recommendation screen that doesn't say which
/// knob to turn is the worst version of this feature.
nonisolated enum RecommendationGenerationError: Error, Equatable, LocalizedError {
    /// The pantry could not be read (Firestore unavailable, signed out).
    case pantryInformationUnavailable
    /// The pantry was read successfully and is empty.
    case pantryNeedsIngredients
    /// The recipe catalogue could not be read.
    case recipeCatalogueUnavailable
    /// The catalogue was read successfully and has no recipes in it.
    case recipeCatalogueEmpty
    /// Recipes were evaluated, and everything that could have been cooked
    /// was removed by a preference the user can relax.
    case filtersExcludeFeasibleRecipes
    /// Recipes were evaluated and none were close enough to cookable.
    case noRealisticallySuitableRecipes
    /// Every remaining recipe was skipped by the user in this session.
    case everyRecipeSkippedInSession
    /// The context asked for a restriction FridgeFit cannot assess from
    /// recipe ingredients, such as gluten-free or nut-free.
    ///
    /// Fails the whole run rather than returning a filtered list, because
    /// any list returned under this filter would imply a check that was
    /// never performed. The preference form does not offer these, so this
    /// is a guard against a context built in code - see
    /// `DietaryRestriction.assessmentBasis`.
    case dietaryRestrictionNotAssessable(Set<DietaryRestriction>)

    /// Picks the clearest explanation for a run that evaluated recipes but
    /// produced nothing to show.
    ///
    /// Ordered by what the user can act on: if the only thing standing
    /// between them and a meal is a filter they set a moment ago, say so
    /// rather than implying their pantry is the problem.
    static func emptyResult(
        exclusionReasons: [RecipeExclusionReason],
        skippedRecipeCount: Int,
        evaluatedRecipeCount: Int
    ) -> RecommendationGenerationError {
        if evaluatedRecipeCount == 0 && skippedRecipeCount > 0 {
            return .everyRecipeSkippedInSession
        }

        guard !exclusionReasons.isEmpty else {
            return .noRealisticallySuitableRecipes
        }

        if exclusionReasons.allSatisfy(\.isContextFilterExclusion) {
            return .filtersExcludeFeasibleRecipes
        }

        return .noRealisticallySuitableRecipes
    }

    var errorDescription: String? {
        switch self {
        case .pantryInformationUnavailable:
            return "FridgeFit couldn't load your pantry."
        case .pantryNeedsIngredients:
            return "Your pantry is empty."
        case .recipeCatalogueUnavailable:
            return "FridgeFit couldn't load its recipes."
        case .recipeCatalogueEmpty:
            return "There are no recipes to recommend yet."
        case .filtersExcludeFeasibleRecipes:
            return "Your cooking preferences ruled out every available meal."
        case .noRealisticallySuitableRecipes:
            return "No meal is close enough to cookable with your pantry right now."
        case .everyRecipeSkippedInSession:
            return "You've skipped every meal in this session."
        case .dietaryRestrictionNotAssessable(let restrictions):
            let names = restrictions
                .map(\.displayName)
                .sorted()
                .joined(separator: " and ")
            return "FridgeFit can't check \(names)."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .pantryInformationUnavailable:
            return "Check your connection and try again."
        case .pantryNeedsIngredients:
            return "Add a few ingredients in Pantry or Kitchen, then try again."
        case .recipeCatalogueUnavailable:
            return "Try again in a moment."
        case .recipeCatalogueEmpty:
            return "Check back later for recipes to cook."
        case .filtersExcludeFeasibleRecipes:
            return "Relax your time, difficulty, or dietary preferences."
        case .noRealisticallySuitableRecipes:
            return "Add more ingredients, or allow meals that need one or two additions."
        case .everyRecipeSkippedInSession:
            return "Start a new session to see those meals again."
        case .dietaryRestrictionNotAssessable:
            return "It knows each recipe's ingredient names, not the brands or processing behind them. Remove this requirement to see ingredient-based matches, and check the packaging yourself."
        }
    }

    /// The preference form is the fix for this failure, so the UI offers it
    /// as the primary action rather than a bare "Try Again".
    var isResolvedByAdjustingPreferences: Bool {
        self == .filtersExcludeFeasibleRecipes
    }
}
