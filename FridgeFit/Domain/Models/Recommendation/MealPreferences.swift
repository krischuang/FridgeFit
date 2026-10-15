//
//  MealPreferences.swift
//  FridgeFit
//

import Foundation

/// The broad cuisine style of a recipe, and of a user's preference.
///
/// A fixed set rather than free text so a preference and a recipe label
/// can be compared exactly - the ranking rule is "does the recipe's
/// cuisine appear in the set the user picked", which needs both sides to
/// come from the same vocabulary.
nonisolated enum Cuisine: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case asian
    case italian
    case mexican
    case mediterranean
    case comfortFood

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .asian: return "Asian"
        case .italian: return "Italian"
        case .mexican: return "Mexican"
        case .mediterranean: return "Mediterranean"
        case .comfortFood: return "Comfort Food"
        }
    }
}

/// The taste characteristics a user may prefer.
///
/// Influences ranking only - a taste mismatch never excludes a recipe,
/// because wanting something fresh is a preference, not a constraint.
nonisolated enum TastePreference: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case savoury
    case spicy
    case fresh
    case mild
    case hearty

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .savoury: return "Savoury"
        case .spicy: return "Spicy"
        case .fresh: return "Fresh"
        case .mild: return "Mild"
        case .hearty: return "Hearty"
        }
    }
}

/// A dietary restriction the recommendation flow must respect.
///
/// ## Why these are handled differently from cuisine and taste
///
/// These are the only preferences treated as a hard constraint, and the
/// only ones where *missing* recipe metadata excludes a recipe instead of
/// merely ranking it lower. Someone who selects `nutFree` is not
/// expressing a preference, and a recipe whose labels were never recorded
/// is not evidence of compliance - see `DietaryCompliance`.
nonisolated enum DietaryRestriction: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case vegetarian
    case vegan
    case dairyFree
    case glutenFree
    case nutFree

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .dairyFree: return "Dairy Free"
        case .glutenFree: return "Gluten Free"
        case .nutFree: return "Nut Free"
        }
    }
}
