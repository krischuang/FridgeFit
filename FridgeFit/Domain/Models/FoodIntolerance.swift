//
//  FoodIntolerance.swift
//  FridgeFit
//

import Foundation

/// A food the user must avoid (allergy or intolerance). Raw values match
/// Spoonacular's `intolerances` parameter.
///
/// ## Business rule
///
/// An intolerance is a safety constraint, not a taste preference - a recipe
/// whose ingredients can't be verified is treated as unsafe rather than
/// shown (see `FindOnlineRecipesFromPantryUseCase`).
///
/// ## Why only some of these are selectable
///
/// `assessmentBasis` applies the standard `DietaryRestriction` already
/// established on `main`, to the same evidence FridgeFit actually holds:
/// recipe ingredient *names*, with no brands, no processing information and
/// no allergen declarations.
///
/// - `.composition` - settled by what the dish is made of. Cream is dairy
///   whatever brand it is, and a named prawn is shellfish however it was
///   bought. These stay selectable.
/// - `.productProvenance` - settled only by the specific products in
///   someone's kitchen. Gluten, wheat, peanut and tree nut turn on brand,
///   processing and shared equipment, and for coeliac disease or a nut
///   allergy a trace is the whole problem. Sulfites are an added
///   preservative that appears in no ingredient name at all.
///
/// The provenance-grade cases are listed in the filter UI in a separate,
/// non-selectable section that says why - exactly as `CookingContextFormView`
/// does for `glutenFree` and `nutFree`. A filter that implies a check the
/// app never performed is worse than no filter: it reads as "this is safe
/// for you" when the truth is "FridgeFit cannot tell you".
nonisolated enum FoodIntolerance: String, CaseIterable, Identifiable, Codable {
    case dairy
    case egg
    case gluten
    case grain
    case peanut
    case seafood
    case sesame
    case shellfish
    case soy
    case sulfite
    case treeNut = "Tree Nut"
    case wheat

    var id: String { rawValue }

    var apiValue: String { rawValue }

    var displayName: String {
        switch self {
        case .dairy: return "Dairy"
        case .egg: return "Egg"
        case .gluten: return "Gluten"
        case .grain: return "Grain"
        case .peanut: return "Peanut"
        case .seafood: return "Seafood"
        case .sesame: return "Sesame"
        case .shellfish: return "Shellfish"
        case .soy: return "Soy"
        case .sulfite: return "Sulfite"
        case .treeNut: return "Tree Nut"
        case .wheat: return "Wheat"
        }
    }

    /// What kind of evidence this intolerance needs before FridgeFit will
    /// offer it as a filter. Shares `DietaryRestriction`'s vocabulary so
    /// there is one standard in the app, not two.
    var assessmentBasis: DietaryAssessmentBasis {
        switch self {
        case .dairy, .egg, .grain, .seafood, .sesame, .shellfish, .soy:
            return .composition
        case .gluten, .wheat, .peanut, .treeNut, .sulfite:
            return .productProvenance
        }
    }

    /// Whether FridgeFit can answer this from a recipe's ingredient names.
    var isAssessableFromIngredients: Bool {
        assessmentBasis == .composition
    }

    /// Why this intolerance cannot be matched, for the UI to show instead
    /// of a selectable control. `nil` when it can be matched.
    var unassessableExplanation: String? {
        switch self {
        case .dairy, .egg, .grain, .seafood, .sesame, .shellfish, .soy:
            return nil
        case .gluten, .wheat:
            return "Depends on the brand of flour, stock, sauce or spice blend a recipe was written around, and on shared equipment. For coeliac disease a trace matters, so FridgeFit doesn't offer this as a filter."
        case .peanut, .treeNut:
            return "The absence of a nut from an ingredient list is not evidence of nut safety - \"may contain\" labelling and shared equipment are the real risk. Check the packaging yourself."
        case .sulfite:
            return "Sulfites are an added preservative that appears in no ingredient name, so an ingredient list cannot rule them out."
        }
    }

    /// The intolerances FridgeFit will match against a recipe, and the only
    /// ones the filter UI lets the user select.
    static var assessableCases: [FoodIntolerance] {
        allCases.filter(\.isAssessableFromIngredients)
    }

    /// The intolerances FridgeFit deliberately does not claim.
    static var unassessableCases: [FoodIntolerance] {
        allCases.filter { !$0.isAssessableFromIngredients }
    }
}
