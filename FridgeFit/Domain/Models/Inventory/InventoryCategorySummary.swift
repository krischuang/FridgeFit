//
//  InventoryCategorySummary.swift
//  FridgeFit
//

import Foundation

/// Which kind of food the kitchen screen is narrowed to.
///
/// The four summary tiles on My Fridge, mapped onto FridgeFit's real
/// ingredient categories. Presentation state only, like `InventoryFilter`
/// beside it - it changes what is listed and never changes a stored item.
///
/// It composes with `InventoryFilter` rather than replacing it: storage
/// answers "where is it" and this answers "what is it", so Freezer +
/// Proteins is a meaningful pair and neither selection clears the other.
nonisolated enum InventoryCategorySummary: String, CaseIterable, Identifiable, Sendable {
    case all
    case produce
    case proteins
    case dairyAndPantry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .produce: return "Produce"
        case .proteins: return "Proteins"
        case .dairyAndPantry: return "Dairy & Pantry"
        }
    }

    /// The category whose photo stands in for the tile.
    ///
    /// `nil` for `.all`, which shows the whole-pantry artwork instead of
    /// electing one category to represent every other.
    var representativeCategory: IngredientCategory? {
        switch self {
        case .all: return nil
        case .produce: return .produce
        case .proteins: return .meat
        case .dairyAndPantry: return .dairy
        }
    }

    /// Whether an item of this category belongs under this tile.
    ///
    /// `.other` sits with Dairy & Pantry rather than nowhere. These four
    /// tiles are the only category filter on the screen, so a category left
    /// out of all of them would be reachable from All and from no other tile
    /// - the user would see it counted but never be able to narrow to it.
    /// The pantry shelf is where an uncategorised staple lives anyway.
    func includes(_ category: IngredientCategory) -> Bool {
        switch self {
        case .all:
            return true
        case .produce:
            return category == .produce
        case .proteins:
            return category == .meat
        case .dairyAndPantry:
            return [.dairy, .grain, .spice, .other].contains(category)
        }
    }
}
