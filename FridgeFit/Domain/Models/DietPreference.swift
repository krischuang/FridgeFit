//
//  DietPreference.swift
//  FridgeFit
//

import Foundation

/// An eating style the online recipe search should honour. Raw values are
/// the exact strings Spoonacular's `diet` parameter expects.
///
/// ## What this is, and what it is not
///
/// Every case here is a **provider-side narrowing of the search**, not a
/// claim FridgeFit makes about a recipe. The value is forwarded as the
/// `diet` query parameter and the provider decides what comes back;
/// FridgeFit never labels a returned recipe as compliant, and
/// `SaveOnlineRecipeUseCase` deliberately leaves `Recipe.dietaryLabels`
/// `nil` on everything saved from Discover. A saved online recipe is
/// therefore `DietaryCompliance.unknown` and is withheld whenever the user
/// has selected a dietary restriction - which is the same standard
/// `main` applies to an unlabelled bundled recipe.
///
/// ## Why gluten-free is absent
///
/// The source branch offered a `glutenFree` diet. It is not here, and that
/// is deliberate rather than an oversight. `DietaryRestriction` classifies
/// gluten-free as `.productProvenance`: answerable only from the specific
/// products in someone's kitchen, never from an ingredient name. FridgeFit
/// claims it on no recipe and does not offer it as a filter. Offering it
/// *here*, against third-party data, would be strictly worse - a coeliac
/// would be choosing a filter whose result the app cannot stand behind.
///
/// The remaining cases are eating styles rather than safety constraints: a
/// missed match is a diet slip, not a hospital visit. See
/// `FoodIntolerance` for the constraints that *are* treated as safety
/// questions.
nonisolated enum DietPreference: String, CaseIterable, Identifiable, Codable {
    case none
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
