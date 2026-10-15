//
//  Shim.swift
//  vision-eval swift harness
//
//  The smallest set of app types the recogniser files reference that are not
//  themselves part of the recognition pipeline. Only `IngredientCategory`
//  qualifies: `IngredientGroup.pantryCategory` maps onto the Pantry's own
//  enum, and pulling in Ingredient.swift would drag in SwiftUI and the whole
//  pantry domain for one switch statement.
//
//  Kept byte-identical in case order to FridgeFit/Domain/Models/Ingredient.swift.
import Foundation

enum IngredientCategory: String, Codable, CaseIterable, Identifiable {
    case produce = "Produce"
    case dairy = "Dairy"
    case meat = "Meat"
    case grain = "Grain"
    case spice = "Spice & Condiment"
    case other = "Other"

    var id: String { rawValue }
}
