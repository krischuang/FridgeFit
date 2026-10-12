//
//  FoodIntolerance.swift
//  FridgeFit
//

import Foundation

/// A food the user must avoid (allergy or intolerance). Raw values match
/// Spoonacular's `intolerances` parameter.
///
/// Business rule: an intolerance is a safety constraint, not a taste
/// preference - a recipe whose ingredients can't be verified is treated as
/// unsafe rather than shown (see `FindOnlineRecipesFromPantryUseCase`).
enum FoodIntolerance: String, CaseIterable, Identifiable, Codable {
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
}
