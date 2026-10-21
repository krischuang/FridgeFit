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
/// - the provider explicitly reported it in `usedIngredients` - which it
///   does only when it matched one of the pantry names we sent, so it is
///   still evidence from the user's own pantry (e.g. pantry "beef" covering
///   "ground beef").
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

        var have: [String] = []
        var missing: [OnlineRecipeIngredient] = []
        for ingredient in ingredients {
            let inPantry = pantry.contains { OnlineRecipeExpiryRanking.namesMatch(ingredient.name, $0.name) }
            let reportedUsed = match.usedIngredientNames.contains {
                OnlineRecipeExpiryRanking.namesMatch($0, ingredient.name)
            }
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
}
