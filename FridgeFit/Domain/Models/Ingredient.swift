//
//  Ingredient.swift
//  FridgeFit
//

import Foundation

/// A food ingredient, like "Chicken Breast" or "Greek Yogurt". Just a name
/// and a category - quantity only makes sense once it's placed in the
/// pantry (`PantryItem`).
struct Ingredient: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var category: IngredientCategory

    init(id: UUID = UUID(), name: String, category: IngredientCategory = .other) {
        self.id = id
        self.name = name
        self.category = category
    }

    /// Whether this ingredient's name matches `otherName`, ignoring
    /// case/whitespace - so "greek yogurt" matches "Greek Yogurt".
    func matches(name otherName: String) -> Bool {
        Self.normalized(name) == Self.normalized(otherName)
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// A rough grouping for organizing the pantry and picking an icon.
enum IngredientCategory: String, Codable, CaseIterable, Identifiable {
    case produce = "Produce"
    case dairy = "Dairy"
    case meat = "Meat"
    case grain = "Grain"
    case spice = "Spice & Condiment"
    case other = "Other"

    var id: String { rawValue }

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
