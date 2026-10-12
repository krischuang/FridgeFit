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

    /// Short human summary for the Discover header, e.g.
    /// "Vegan · no Peanut · ≤ 30 min".
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

    var isFromCache: Bool { matches.contains { $0.isFromCache } }
}
