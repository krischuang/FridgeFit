//
//  BundledPhotoAssets.swift
//  FridgeFit
//

import UIKit

// photos that ship in Assets.xcassets (all from Unsplash, see
// docs/photo-credits.md). bundled recipes and ingredient categories only had
// SF Symbols before - these sit in front of the symbol, and anything without
// a photo just keeps its symbol.
enum BundledPhotoAssets {

    // "Creamy Chicken Pasta" -> "recipe_creamy_chicken_pasta"
    static func recipePhoto(for recipe: Recipe) -> UIImage? {
        UIImage(named: "recipe_" + slug(recipe.title))
    }

    static func categoryPhoto(for category: IngredientCategory) -> UIImage? {
        UIImage(named: "category_" + categoryKey(category))
    }

    // spelled out rather than built from the raw value, because rawValues like
    // "Spice & Condiment" are display text and could change
    static func categoryKey(_ category: IngredientCategory) -> String {
        switch category {
        case .produce: return "produce"
        case .dairy: return "dairy"
        case .meat: return "meat"
        case .grain: return "grain"
        case .spice: return "spice"
        case .other: return "other"
        }
    }

    // lowercase, anything that isn't a letter or digit becomes one underscore
    static func slug(_ title: String) -> String {
        var result = ""
        var lastWasSeparator = true
        for character in title.lowercased() {
            if character.isLetter || character.isNumber {
                result.append(character)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                result.append("_")
                lastWasSeparator = true
            }
        }
        if result.hasSuffix("_") { result.removeLast() }
        return result
    }
}
