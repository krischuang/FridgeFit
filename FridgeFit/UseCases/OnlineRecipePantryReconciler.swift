//
//  OnlineRecipePantryReconciler.swift
//  FridgeFit
//

import Foundation

/// Re-derives which of an online recipe's ingredients the user has, from
/// the user's real pantry, instead of trusting "not reported missing".
///
/// ## Why
///
/// Spoonacular assumes common pantry staples (sugar, salt, flour, water...)
/// are on hand and leaves them out of `missedIngredients`. Treating "not in
/// the missed list" as "you have it" made a Baked Custard read "2 of 4
/// matched" (eggs, brown sugar) for a pantry holding only egg and beef.
///
/// ## Rule
///
/// For every line of the recipe's ingredient list, it counts as **have**
/// only if either:
/// - it matches an item in the user's pantry (`OnlineRecipeExpiryRanking.namesMatch`,
///   i.e. the app-wide `IngredientNameMatching` rule), or
/// - the provider explicitly reported it in `usedIngredients` **and** some
///   in-stock pantry item's name is still *part of* the ingredient's (every
///   word of the pantry name appears in the ingredient name, so pantry
///   "beef" covers "ground beef"). The provider's report reflects the pantry
///   at search time; this second check stops a used-up or deleted item from
///   staying "have" when results are re-checked without a new search.
///
/// Only items with a quantity above zero count: using an item up leaves it
/// in the pantry at zero, and that is not "have".
///
/// Everything else is **missing**. `usedIngredientNames` becomes the have
/// lines and `missedIngredients` the rest, so every count, the ranking, the
/// expiry badges and the detail screen read the same answer.
///
/// A recipe without an ingredient list is left as the provider sent it -
/// there is nothing to re-derive from.
nonisolated enum OnlineRecipePantryReconciler {
    static func reconciled(_ match: OnlineRecipeMatch, pantry: [PantryItem]) -> OnlineRecipeMatch {
        let ingredients = match.recipe.ingredients
        guard !ingredients.isEmpty else { return match }

        let inStock = pantry.filter { $0.quantity > 0 }

        var have: [String] = []
        var missing: [OnlineRecipeIngredient] = []
        for ingredient in ingredients {
            let inPantry = inStock.contains { OnlineRecipeExpiryRanking.namesMatch(ingredient.name, $0.name) }
            let reportedUsed = match.usedIngredientNames.contains {
                OnlineRecipeExpiryRanking.namesMatch($0, ingredient.name)
            } && isCovered(ingredient.name, byAnyOf: inStock)
            if inPantry || reportedUsed {
                have.append(ingredient.name)
            } else {
                missing.append(ingredient)
            }
        }

        var reconciled = match
        reconciled.usedIngredientNames = have
        reconciled.missedIngredients = missing
        return reconciled
    }

    /// Whether one in-stock item's name is *part of* `ingredientName` -
    /// every word of the pantry name appears in the ingredient name, so
    /// pantry "beef" covers "ground beef" but "ground pork" does not.
    ///
    /// Per item and directional on purpose. Pooling every in-stock word and
    /// asking "do these overlap?" let an unrelated item supply the shared
    /// word: with "ground pork" in the pantry and no beef at all, "ground
    /// beef" stayed `have` on the word "ground", and a pantry "cheddar
    /// cheese" kept "cream cheese" on the word "cheese". Both are the false
    /// "you have it" this type exists to prevent. A subset test cannot do
    /// that, because neither pantry name is contained in the ingredient.
    private static func isCovered(_ ingredientName: String, byAnyOf inStock: [PantryItem]) -> Bool {
        let ingredientWords = Set(words(of: ingredientName))
        guard !ingredientWords.isEmpty else { return false }
        return inStock.contains { item in
            let itemWords = Set(words(of: item.name))
            return !itemWords.isEmpty && itemWords.isSubset(of: ingredientWords)
        }
    }

    /// The matching words of a name, after the same normalisation Discover
    /// uses everywhere (descriptors, plurals, case).
    private static func words(of name: String) -> [String] {
        OnlineRecipeExpiryRanking.matchKey(name).split(separator: " ").map(String.init)
    }
}
