//
//  ReceiptItemClassification.swift
//  FridgeFit
//

import Foundation

/// What kind of thing a receipt line turned out to be.
///
/// The distinction that matters to FridgeFit is not "food vs not food" but
/// "would a recipe ever call for this". A bottle of cola and a chocolate bar
/// are both food and neither is a pantry ingredient, so they get their own
/// cases rather than being lumped in with chicken breast.
///
/// `shouldAddToPantry` is derived here, in one place, rather than being
/// asked of the model. The model's job is to classify; the product decision
/// about which classifications reach the pantry is ours, and changing it
/// later means editing this one property.
nonisolated enum ReceiptItemClassification: String, Codable, CaseIterable, Equatable {
    /// Something a recipe could call for: produce, meat, dairy, staples.
    case ingredient
    /// Edible, but not something you cook with - a chocolate bar, a packet
    /// of crisps, a ready meal.
    case foodNonIngredient
    /// Drinks. Split out from `foodNonIngredient` because a few (milk,
    /// stock, juice) genuinely are cooking ingredients, so the boundary is
    /// worth being able to move independently.
    case beverage
    /// Cleaning products, kitchen roll, bin bags, pet food.
    case household
    /// Toiletries, cosmetics, medicine.
    case personalCare
    /// The line could not be resolved confidently. Deliberately not a
    /// guess - see `ReceiptInterpretationPromptBuilder`.
    case unknown

    /// Whether an item of this kind is offered as a pantry candidate.
    ///
    /// Only `ingredient` qualifies. Everything else is still parsed,
    /// classified and available to DEBUG diagnostics, but never clutters
    /// the confirmation screen.
    var shouldAddToPantry: Bool { self == .ingredient }

    /// Short label for DEBUG diagnostics. Not user-facing.
    var diagnosticLabel: String { rawValue }
}
