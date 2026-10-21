//
//  OnlineIngredientName.swift
//  FridgeFit
//

import Foundation

/// Conservative tidying of a provider's ingredient name.
///
/// ## What this does, and the much larger thing it refuses to do
///
/// Online ingredient names and pantry item names come from two different
/// vocabularies. `EvaluateRecipeFeasibilityUseCase` matches them with
/// `Ingredient.matches(name:)` - case-, whitespace- and plural-insensitive
/// equality (`IngredientNameMatching`), so "Eggs" matches "Egg" but
/// "garlic cloves" does not match a pantry item called "Garlic", and a
/// recipe saved from Discover will often read as missing an ingredient the
/// user actually has.
///
/// The tempting fix is a synonym table: strip preparation words, fold
/// "garlic cloves" onto "garlic". That is **not** done here,
/// because every such rule is a guess about ingredient identity, and the
/// failure mode points the wrong way. Folding "coconut milk" onto "milk",
/// or "green onion" onto "onion", would make the feasibility engine report
/// an ingredient as present that the user does not have - turning a name
/// heuristic into a quantity claim, which is the one thing the engine is
/// built never to do. Under-matching is visible and honest: the recipe says
/// an ingredient is missing. Over-matching is invisible and wrong.
///
/// So this type does only what cannot change what an ingredient *is*:
///
/// - trims surrounding whitespace
/// - removes parenthetical asides, which are packaging or preparation notes
///   rather than part of the identity ("tomatoes (14 oz can)")
/// - collapses runs of internal whitespace
///
/// Cross-vocabulary matching remains an open problem, recorded as such.
/// `OnlineRecipeIngredient.providerID` is captured and carried through for
/// exactly that future work: the provider's own ingredient id is a far
/// better key for a mapping table than any string rule, and a table built
/// from it could be reviewed entry by entry instead of inferred.
nonisolated enum OnlineIngredientName {

    /// Tidies `raw` without altering which ingredient it names.
    ///
    /// Returns an empty string when nothing usable is left, which callers
    /// treat as "no name" rather than substituting a placeholder.
    static func normalized(_ raw: String) -> String {
        let withoutParentheticals = raw.replacingOccurrences(
            of: "\\([^)]*\\)",
            with: " ",
            options: .regularExpression
        )
        return withoutParentheticals
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Title-cased for display, preserving the words `normalized` produced.
    ///
    /// Uses `capitalized` on each word rather than
    /// `String.capitalized` on the whole phrase so that an already-uppercase
    /// provider name is not left shouting.
    static func displayName(_ raw: String) -> String {
        normalized(raw)
            .split(separator: " ")
            .map { $0.lowercased().capitalized }
            .joined(separator: " ")
    }
}
