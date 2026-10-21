//
//  IngredientNameMatching.swift
//  FridgeFit
//

import Foundation

/// The one rule for "do these two names mean the same ingredient?".
///
/// Used by `Ingredient.matches(name:)` - so by feasibility, recommendations,
/// substitution validation, receipt scanning and the pantry's duplicate
/// check - and by the Discover expiry ranking, so every screen agrees.
///
/// ## What it folds
///
/// Only differences that cannot change which food is meant:
/// - letter case and surrounding / repeated whitespace,
/// - **singular vs plural**, word by word: "Eggs" = "egg",
///   "Cherry Tomatoes" = "cherry tomato", "berries" = "berry",
///   "bay leaves" = "bay leaf".
///
/// ## What it deliberately does not fold
///
/// No synonyms and no dropped words. "fresh spinach" is not "spinach",
/// "coconut milk" is not "milk", "green onion" is not "onion". Each of those
/// would let the feasibility engine report an ingredient the user doesn't
/// have - a false "you can make this". A missed match is visible (the
/// recipe says it's missing); a false match is not. Synonym handling for
/// receipts stays in `IngredientCanonicalizer`, which builds on this.
nonisolated enum IngredientNameMatching {

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let key = matchKey(lhs)
        return !key.isEmpty && key == matchKey(rhs)
    }

    /// Lowercased, whitespace-collapsed, every word singularized.
    static func matchKey(_ name: String) -> String {
        name.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map { singularized(String($0)) }
            .joined(separator: " ")
    }

    /// English plural → singular for food words. Rules, in order:
    /// irregulars ("leaves" → "leaf"); "-ies" → "-y"; "-oes" → "-o";
    /// "-ses/-xes/-zes/-ches/-shes" → drop "es"; words ending "-ss", "-us",
    /// "-is" are left alone ("swiss", "hummus", "asparagus"); otherwise a
    /// trailing "s" is dropped. Words of three letters or fewer are left
    /// alone ("gas", "yes").
    static func singularized(_ word: String) -> String {
        if let irregular = irregularSingulars[word] { return irregular }
        guard word.count > 3 else { return word }

        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("oes") { return String(word.dropLast(2)) }
        for suffix in ["ses", "xes", "zes", "ches", "shes"] where word.hasSuffix(suffix) {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("ss") || word.hasSuffix("us") || word.hasSuffix("is") { return word }
        if word.hasSuffix("s") { return String(word.dropLast()) }
        return word
    }

    private static let irregularSingulars: [String: String] = [
        "leaves": "leaf",
        "loaves": "loaf",
        "halves": "half",
        "knives": "knife",
    ]
}
