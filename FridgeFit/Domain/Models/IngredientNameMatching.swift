//
//  IngredientNameMatching.swift
//  FridgeFit
//

import Foundation

/// The app's ingredient-name vocabulary: one place that decides when two
/// names mean the same food, and when a pantry item satisfies what a recipe
/// asks for.
///
/// ## Two questions
///
/// They are not the same question, so there are two entry points - but both
/// are built from the folds below, and each question has exactly one answer
/// everywhere in the app.
///
/// - **"Is this the same pantry entry?"** - `matches` / `matchKey`. Strict:
///   no words dropped. Used by the pantry's duplicate check
///   (`AddPantryItemUseCase`), receipt scanning (`ScanReceiptUseCase`,
///   `IngredientCanonicalizer`) and the ingredient editor's lookup. Being
///   strict here is deliberate: someone may want "fresh basil" and "dried
///   basil" as separate entries with separate expiry dates.
/// - **"Does the pantry cover this requirement?"** - `covers` /
///   `coverageKey`. Everything `matchKey` folds, **plus leading descriptor
///   words**. Used by `EvaluateRecipeFeasibilityUseCase` (Recipes, Saved
///   Recipes, recommendations), `EvaluateRecipeSuitabilityUseCase`,
///   `SuggestRecipesFromPantryUseCase`, `SubstitutionSuggestionValidator`
///   and Discover (`OnlineRecipeExpiryRanking`,
///   `OnlineRecipePantryReconciler`).
///
/// Every "do I have it?" surface goes through `covers`, so Discover and
/// Recipes cannot disagree: a recipe whose ingredient reads "Matched" in
/// Discover does not flip to "Missing" once it is saved.
///
/// ## What both fold
///
/// Only differences that cannot change which food is meant:
/// - letter case and surrounding / repeated whitespace,
/// - **singular vs plural**, word by word: "Eggs" = "egg",
///   "Cherry Tomatoes" = "cherry tomato", "berries" = "berry",
///   "bay leaves" = "bay leaf".
///
/// ## What neither folds
///
/// No synonyms, and no dropped word that could change the food. "coconut
/// milk" is not "milk", "green onion" is not "onion", "brown sugar" is not
/// "sugar", "egg whites" are not "eggs". Each would let the feasibility
/// engine report an ingredient the user doesn't have - a false "you can make
/// this". A missed match is visible (the recipe says it's missing); a false
/// match is not. Synonym handling for receipts stays in
/// `IngredientCanonicalizer`, which builds on this.
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

    // MARK: - Coverage

    /// Whether a pantry item named `pantryName` satisfies a recipe asking
    /// for `recipeName` - the "do I have it?" question. See the type's note
    /// on the two questions.
    ///
    /// The parameter names document intent rather than a direction: the
    /// comparison is symmetric, because either side may be the one carrying
    /// the descriptor ("mild cheddar cheese" in the recipe and "Cheddar
    /// Cheese" in the pantry, or the other way round).
    static func covers(pantryName: String, recipeName: String) -> Bool {
        let key = coverageKey(recipeName)
        return !key.isEmpty && key == coverageKey(pantryName)
    }

    /// `matchKey` after dropping leading descriptor words.
    static func coverageKey(_ name: String) -> String {
        matchKey(withoutLeadingDescriptors(name))
    }

    /// Words that describe *how* an ingredient is bought or prepared, not
    /// *which* ingredient it is - "mild cheddar cheese" is cheddar cheese,
    /// "large eggs" are eggs. Deliberately excludes words that change the
    /// ingredient ("brown" sugar, "sweet" potato, "green" onion, "light"
    /// cream), so those still need an exact match on both questions.
    static let descriptorWords: Set<String> = [
        "mild", "medium", "sharp", "mature", "aged", "extra", "extra-sharp",
        "fresh", "freshly", "large", "small", "jumbo", "extra-large", "ripe",
        "organic", "raw", "boneless", "skinless", "unsalted", "salted",
        "chopped", "diced", "minced", "sliced", "grated", "shredded",
        "crumbled", "softened", "melted", "cold", "warm", "frozen", "thawed",
        "low-fat", "reduced-fat", "full-fat", "whole", "plain",
    ]

    /// Drops descriptor words from the front of `name`, keeping at least one
    /// word, so a name made only of descriptors is left as it was.
    static func withoutLeadingDescriptors(_ name: String) -> String {
        var words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        while words.count > 1,
              descriptorWords.contains(words[0].lowercased().trimmingCharacters(in: .punctuationCharacters.subtracting(["-"]))) {
            words.removeFirst()
        }
        return words.joined(separator: " ")
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
