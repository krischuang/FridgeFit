//
//  DietPreference.swift
//  FridgeFit
//

import Foundation

/// An eating style the online recipe search should honour. Raw values are
/// the exact strings Spoonacular's `diet` parameter expects.
enum DietPreference: String, CaseIterable, Identifiable, Codable {
    case none
    case glutenFree = "Gluten Free"
    case ketogenic = "Ketogenic"
    case vegetarian = "Vegetarian"
    case lactoVegetarian = "Lacto-Vegetarian"
    case ovoVegetarian = "Ovo-Vegetarian"
    case vegan = "Vegan"
    case pescetarian = "Pescetarian"
    case paleo = "Paleo"
    case primal = "Primal"
    case lowFodmap = "Low FODMAP"
    case whole30 = "Whole30"

    var id: String { rawValue }

    /// `nil` for `.none` - the parameter is then omitted entirely.
    var apiValue: String? { self == .none ? nil : rawValue }

    var displayName: String { self == .none ? "No preference" : rawValue }
}
