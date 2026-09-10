//
//  Recipe.swift
//  FridgeFit
//

import Foundation

/// A dish the user might want to make: a title, its ingredients, and how
/// to cook it.
///
/// Recipe stays simple - quantities, units, and role all live on
/// `RecipeIngredient` so feasibility logic doesn't creep in here.
struct Recipe: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var summary: String
    /// `nil` when the source doesn't specify a serving count.
    var servings: Int?
    var ingredients: [RecipeIngredient]
    /// One entry per step, in cooking order.
    var instructions: [String]
    /// SF Symbol name for the recipe list/detail icon. Optional since not
    /// every source will provide one - no photo pipeline in this phase.
    var symbolName: String?

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        servings: Int? = nil,
        ingredients: [RecipeIngredient],
        instructions: [String],
        symbolName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.servings = servings
        self.ingredients = ingredients
        self.instructions = instructions
        self.symbolName = symbolName
    }
}
