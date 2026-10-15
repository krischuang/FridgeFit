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

/// What kind of evidence a dietary claim needs before FridgeFit will make
/// it.
///
/// This distinction exists because the five restrictions FridgeFit models
/// are not all the same kind of question, and treating them as if they
/// were produced an incoherent standard: gluten-free was being claimed
/// from an ingredient list while nut-free was being withheld on the
/// grounds that an ingredient list cannot establish absence. Both of those
/// cannot be right.
nonisolated enum DietaryAssessmentBasis: Equatable, Hashable, Sendable {
    /// Answerable from what the dish is *made of*. "Does this contain an
    /// animal product" is settled by the ingredient list: cream is dairy
    /// whatever brand it is, and chicken is meat however it was processed.
    case composition

    /// Answerable only from the specific products in the user's kitchen.
    /// Whether a dish is gluten-free or nut-free depends on which brand of
    /// stock, spice blend, cheese or granola was bought, how it was
    /// processed, and what shared equipment it met. A generic ingredient
    /// name cannot settle it, and for coeliac disease or nut allergy a
    /// trace is the whole problem.
    case productProvenance
}

/// A dietary restriction the recommendation flow must respect.
///
/// ## Why these are handled differently from cuisine and taste
///
/// These are the only preferences treated as a hard constraint, and the
/// only ones where *missing* recipe metadata excludes a recipe instead of
/// merely ranking it lower. Someone who selects `vegan` is not expressing
/// a preference, and a recipe whose labels were never recorded is not
/// evidence of compliance - see `DietaryCompliance`.
///
/// ## What FridgeFit will and will not claim
///
/// `assessmentBasis` splits these into what the app can honestly answer
/// and what it cannot. FridgeFit has recipe ingredient *names* and no
/// product data at all: no brands, no processing information, no
/// allergen declarations, no cross-contamination control. That is enough
/// to say "this dish contains no animal product". It is not enough to say
/// "this dish is safe for a coeliac".
///
/// The `productProvenance` cases are therefore never claimed on any
/// recipe and are not offered as filters - see `CookingContextFormView`.
/// Offering a filter the app can never honour is worse than omitting it:
/// it returns an empty list and blames the user's preferences for a
/// limitation that is the app's.
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

    var assessmentBasis: DietaryAssessmentBasis {
        switch self {
        case .vegetarian, .vegan, .dairyFree:
            return .composition
        case .glutenFree, .nutFree:
            return .productProvenance
        }
    }

    /// Whether FridgeFit can answer this from a recipe's ingredients.
    var isAssessableFromIngredients: Bool {
        assessmentBasis == .composition
    }

    /// Why this restriction cannot be matched, for the UI to show instead
    /// of a selectable control. `nil` when it can be matched.
    var unassessableExplanation: String? {
        switch assessmentBasis {
        case .composition:
            return nil
        case .productProvenance:
            return "Depends on the specific products you buy, which FridgeFit doesn't know. Check the packaging yourself."
        }
    }

    /// The restrictions FridgeFit can match against a recipe.
    static var assessableCases: [DietaryRestriction] {
        allCases.filter(\.isAssessableFromIngredients)
    }

    /// The restrictions FridgeFit deliberately does not claim.
    static var unassessableCases: [DietaryRestriction] {
        allCases.filter { !$0.isAssessableFromIngredients }
    }
}
