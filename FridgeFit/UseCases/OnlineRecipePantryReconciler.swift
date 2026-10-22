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

        // Every name is reduced to its match key exactly once. Asking
        // `namesMatch` inside the ingredient x pantry loop re-derived both
        // keys on every comparison, which for a page of results is tens of
        // thousands of string splits per pantry change.
        // Materialised, not lazy: it is walked once per ingredient, and a
        // lazy chain would re-normalise on every pass.
        let inStock: [StockedName] = pantry.filter { $0.quantity > 0 }.compactMap(StockedName.init)
        let inStockByKey = Set(inStock.map(\.key))
        let reportedUsedKeys = Set(
            match.usedIngredientNames.map { OnlineRecipeExpiryRanking.matchKey($0) }.filter { !$0.isEmpty }
        )

        var have: [String] = []
        var missing: [OnlineRecipeIngredient] = []
        for ingredient in ingredients {
            let key = OnlineRecipeExpiryRanking.matchKey(ingredient.name)
            let inPantry = !key.isEmpty && inStockByKey.contains(key)
            let reportedUsed = !key.isEmpty
                && reportedUsedKeys.contains(key)
                && isCovered(key, byAnyOf: inStock)
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

    /// An in-stock pantry name, normalised once: its match key and that
    /// key's words, so neither is recomputed per ingredient.
    private struct StockedName {
        let key: String
        let words: Set<String>

        /// `nil` for a name that normalises to nothing - it can neither
        /// match nor cover anything.
        init?(_ item: PantryItem) {
            let key = OnlineRecipeExpiryRanking.matchKey(item.name)
            guard !key.isEmpty else { return nil }
            self.key = key
            self.words = Set(key.split(separator: " ").map(String.init))
        }
    }

    /// Whether one in-stock item's name is *part of* the ingredient whose
    /// match key is `ingredientKey` - every word of the pantry name appears
    /// in the ingredient name, so pantry "beef" covers "ground beef" but
    /// "ground pork" does not.
    ///
    /// Per item and directional on purpose. Pooling every in-stock word and
    /// asking "do these overlap?" let an unrelated item supply the shared
    /// word: with "ground pork" in the pantry and no beef at all, "ground
    /// beef" stayed `have` on the word "ground", and a pantry "cheddar
    /// cheese" kept "cream cheese" on the word "cheese". Both are the false
    /// "you have it" this type exists to prevent. A subset test cannot do
    /// that, because neither pantry name is contained in the ingredient.
    private static func isCovered(_ ingredientKey: String, byAnyOf inStock: [StockedName]) -> Bool {
        let ingredientWords = Set(ingredientKey.split(separator: " ").map(String.init))
        guard !ingredientWords.isEmpty else { return false }
        return inStock.contains { $0.words.isSubset(of: ingredientWords) }
    }
}
