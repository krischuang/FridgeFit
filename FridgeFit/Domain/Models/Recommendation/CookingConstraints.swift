//
//  CookingConstraints.swift
//  FridgeFit
//

import Foundation

/// How demanding a recipe is for a home cook.
///
/// `Comparable` on the raw value so the context filter reads as
/// `recipe.difficulty > context.maximumDifficulty` rather than as a
/// lookup table.
nonisolated enum CookingDifficulty: Int, CaseIterable, Codable, Comparable, Hashable, Identifiable, Sendable {
    case easy = 1
    case moderate = 2
    case challenging = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .easy: return "Easy"
        case .moderate: return "Moderate"
        case .challenging: return "Challenging"
        }
    }

    static func < (lhs: CookingDifficulty, rhs: CookingDifficulty) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The maximum total time the user has to prepare and cook a meal.
///
/// The raw value is the limit in minutes, so the filter compares directly
/// against `Recipe.totalCookingTimeInMinutes` with no mapping step.
nonisolated enum CookingTimeLimit: Int, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case fortyFiveMinutes = 45
    case sixtyMinutes = 60

    var id: Int { rawValue }

    var displayName: String { "Up to \(rawValue) minutes" }
}
