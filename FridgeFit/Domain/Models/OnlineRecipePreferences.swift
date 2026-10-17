//
//  OnlineRecipePreferences.swift
//  FridgeFit
//

import Foundation

/// The user's standing filters for online recipe search. Persisted locally
/// (see `OnlineRecipePreferencesStoring`) so they survive relaunches.
struct OnlineRecipePreferences: Hashable, Codable {
    var diet: DietPreference = .none
    var intolerances: Set<FoodIntolerance> = []
    /// Upper bound on total prep + cook time; `nil` for no limit.
    var maxReadyTimeMinutes: Int?

    static let `default` = OnlineRecipePreferences()

    /// The same preferences with any intolerance FridgeFit cannot assess
    /// removed.
    ///
    /// Applied when preferences are loaded from storage. A value persisted
    /// by an earlier build - or by any future edit that widens the filter
    /// UI - could name a `.productProvenance` intolerance such as gluten.
    /// Keeping it would be the worse of the two failures available: the
    /// search would appear to be filtering for coeliac safety while doing
    /// keyword matching on ingredient names, which is the claim
    /// `DietaryRestriction` exists to prevent. Dropping it means the filter
    /// only ever promises what it performs, and the Filters screen lists
    /// the dropped ones in its non-selectable section with the reason.
    ///
    /// Deliberately not a `Codable` hook: sanitising on decode would hide
    /// the adjustment from tests. See `OnlineRecipePreferencesStoring`.
    func sanitized() -> OnlineRecipePreferences {
        var copy = self
        copy.intolerances = intolerances.filter(\.isAssessableFromIngredients)
        return copy
    }

    /// Short human summary for the Discover header, e.g.
    /// "Vegan · no Dairy · ≤ 30 min".
    var summary: String {
        var parts: [String] = []
        if diet != .none { parts.append(diet.displayName) }
        if !intolerances.isEmpty {
            let names = intolerances.map(\.displayName).sorted().joined(separator: ", ")
            parts.append("no \(names)")
        }
        if let maxReadyTimeMinutes { parts.append("≤ \(maxReadyTimeMinutes) min") }
        return parts.isEmpty ? "No filters" : parts.joined(separator: " · ")
    }
}

/// Everything one online recipe search needs.
struct OnlineRecipeSearchCriteria: Hashable {
    var pantryIngredientNames: [String]
    var preferences: OnlineRecipePreferences
    /// How many results to request. Kept modest: every result costs
    /// Spoonacular quota points on the free plan.
    var resultLimit: Int = 30
}

/// What a pantry-based online search produced.
struct OnlineRecipeSearchResult: Hashable {
    var matches: [OnlineRecipeMatch]
    /// Recipes the provider returned but the safety filter removed because
    /// they contain - or can't be verified free of - an intolerance.
    var excludedForSafetyCount: Int
    /// Per recipe id: which near-expiry / expired pantry items it would use.
    var expiryUse: [Int: OnlineRecipeExpiryUse] = [:]
    /// Pantry items the ranking prioritised, most urgent first.
    var urgentPantryIngredients: [UrgentIngredientUse] = []

    var isFromCache: Bool { matches.contains { $0.isFromCache } }
}
