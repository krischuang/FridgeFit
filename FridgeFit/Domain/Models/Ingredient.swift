//
//  Ingredient.swift
//  FridgeFit
//

import Foundation

/// A food ingredient, like "Chicken Breast" or "Greek Yogurt". Just a name
/// and a category - quantity only makes sense once it's placed in the
/// pantry (`PantryItem`).
nonisolated struct Ingredient: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var category: IngredientCategory

    init(id: UUID = UUID(), name: String, category: IngredientCategory = .other) {
        self.id = id
        self.name = name
        self.category = category
    }

    /// Whether this ingredient's name means the **same pantry entry** as
    /// `otherName`, ignoring case, whitespace and singular/plural - so
    /// "greek yogurt" matches "Greek Yogurt" and "Egg" matches "Eggs".
    ///
    /// This is the strict question, for duplicate checks and lookups. To ask
    /// whether a pantry item *covers* what a recipe needs, use
    /// `IngredientNameMatching.covers(pantryName:recipeName:)` - it also
    /// folds leading descriptors. See `IngredientNameMatching` for why the
    /// two differ.
    func matches(name otherName: String) -> Bool {
        IngredientNameMatching.matches(name, otherName)
    }
}

/// A rough grouping for organizing the pantry and picking an icon.
///
/// `nonisolated` because it is a plain value with no state: this lets
/// nonisolated summary types (`AtRiskIngredient`) carry a category without
/// their `Equatable`/`Identifiable` conformances crossing into main
/// actor-isolated code. Its `tint` lives in a main-actor extension in
/// `PantryPresentation` and is unaffected.
nonisolated enum IngredientCategory: String, Codable, CaseIterable, Identifiable {
    case produce = "Produce"
    case dairy = "Dairy"
    case meat = "Meat"
    case grain = "Grain"
    case spice = "Spice & Condiment"
    case other = "Other"

    var id: String { rawValue }

    /// The category's name as the user sees it.
    ///
    /// Same string as `rawValue`, named separately so views and search read
    /// as intent rather than as "whatever we happened to persist" - and so
    /// the stored value could change later without a find-and-replace
    /// through the UI.
    var displayName: String { rawValue }

    var symbolName: String {
        switch self {
        case .produce: return "leaf.fill"
        case .dairy: return "drop.fill"
        case .meat: return "fork.knife"
        case .grain: return "square.grid.3x3.fill"
        case .spice: return "flame.fill"
        case .other: return "circle.grid.2x2.fill"
        }
    }
}
