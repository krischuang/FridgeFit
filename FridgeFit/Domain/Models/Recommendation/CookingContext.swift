//
//  CookingContext.swift
//  FridgeFit
//

import Foundation

/// The user's current cooking situation: what they can spend, what they
/// can't eat, and what they feel like.
///
/// ## Hard constraints vs. ranking influence
///
/// Dietary restrictions, maximum cooking time, and maximum difficulty are
/// hard constraints - a recipe that breaks one is excluded. Cuisine,
/// taste, and expiry priority only influence the ordering of recipes that
/// already passed. That split is deliberate and is the reason a long list
/// of preferences does not collapse the results to nothing.
///
/// ## Why this isn't persisted
///
/// Session-scoped on purpose. These are answers to "what do you want
/// *right now*", not a user profile, and main has no preferences
/// collection to write them to. Adding one would mean a new Firestore
/// collection and new security rules for data with a lifetime of a few
/// minutes - see `RecommendationSession` for the same reasoning applied
/// to feedback.
nonisolated struct CookingContext: Equatable, Hashable, Codable, Sendable {
    var maximumCookingTime: CookingTimeLimit
    var maximumDifficulty: CookingDifficulty
    var preferredCuisines: Set<Cuisine>
    var preferredTastes: Set<TastePreference>
    var dietaryRestrictions: Set<DietaryRestriction>
    /// Whether recipes that use food approaching its expiry date should be
    /// ranked ahead of recipes that don't.
    var prioritisesExpiringIngredients: Bool

    init(
        maximumCookingTime: CookingTimeLimit = .sixtyMinutes,
        maximumDifficulty: CookingDifficulty = .challenging,
        preferredCuisines: Set<Cuisine> = [],
        preferredTastes: Set<TastePreference> = [],
        dietaryRestrictions: Set<DietaryRestriction> = [],
        prioritisesExpiringIngredients: Bool = true
    ) {
        self.maximumCookingTime = maximumCookingTime
        self.maximumDifficulty = maximumDifficulty
        self.preferredCuisines = preferredCuisines
        self.preferredTastes = preferredTastes
        self.dietaryRestrictions = dietaryRestrictions
        self.prioritisesExpiringIngredients = prioritisesExpiringIngredients
    }

    /// The least restrictive context: everything allowed, nothing preferred.
    ///
    /// What the Recipes tab opens with, so a user who never touches the
    /// preference form still gets a ranked list rather than an empty one.
    static let unrestricted = CookingContext()

    /// Whether the user has actually expressed anything.
    ///
    /// Used only to decide whether to show "Preferences applied" in the UI;
    /// it never changes the filtering rules.
    var hasExpressedPreferences: Bool {
        maximumCookingTime != CookingContext.unrestricted.maximumCookingTime
            || maximumDifficulty != CookingContext.unrestricted.maximumDifficulty
            || !preferredCuisines.isEmpty
            || !preferredTastes.isEmpty
            || !dietaryRestrictions.isEmpty
    }
}
