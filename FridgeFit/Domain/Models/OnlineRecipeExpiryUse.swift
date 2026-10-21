//
//  OnlineRecipeExpiryUse.swift
//  FridgeFit
//

import Foundation

/// Which of the user's pantry items an online recipe would use up while
/// they're close to expiry - and which it would use after they've expired.
///
/// Built by `OnlineRecipeExpiryRanking` from the provider's
/// `usedIngredientNames`, with urgency from `ExpiryService` - the same
/// authority the Kitchen tab and context-aware recommendations use, so a
/// Discover result can never call something urgent that the Kitchen tab
/// calls fine.
nonisolated struct OnlineRecipeExpiryUse: Hashable, Sendable {
    /// Pantry items near expiry (not yet expired), most urgent first.
    var urgent: [UrgentIngredientUse] = []
    /// Pantry items this recipe would use that have already expired.
    var expired: [String] = []

    static let none = OnlineRecipeExpiryUse()

    var usesUrgentIngredient: Bool { !urgent.isEmpty }
    var usesExpiredIngredient: Bool { !expired.isEmpty }
    var mostUrgent: ExpiryUrgency? { urgent.first?.urgency }
}
