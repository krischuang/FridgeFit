//
//  RecipeIntoleranceAnalysis.swift
//  FridgeFit
//

import Foundation

/// Derives which intolerances a recipe contains from its ingredient names,
/// cross-checked against Spoonacular's own "free from" flags.
///
/// Exists because the safety filter must not blindly trust provider tags.
/// Deliberately best-effort keyword matching that errs towards
/// *over*-reporting: for an allergy filter, a false positive is a missed
/// meal; a false negative is a hospital visit. Returns `nil` when there are
/// no names to analyse - callers treat that as unverified.
enum RecipeIntoleranceAnalysis {
    static func intolerances(
        inIngredientNames names: [String],
        knownDairyFree: Bool = false,
        knownGlutenFree: Bool = false,
        vegan: Bool = false,
        vegetarian: Bool = false
    ) -> Set<FoodIntolerance>? {
        let cleaned = names
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }

        var found: Set<FoodIntolerance> = []
        for (intolerance, keywords) in keywordsByIntolerance {
            let hit = keywords.contains { keyword in cleaned.contains { $0.contains(keyword) } }
            if hit { found.insert(intolerance) }
        }

        // Provider's positive "free from" signals override keyword false
        // positives (e.g. "coconut milk" in a dairy-free recipe).
        if knownDairyFree { found.remove(.dairy) }
        if knownGlutenFree { found.remove(.gluten); found.remove(.wheat) }
        if vegan { found.subtract([.dairy, .egg, .seafood, .shellfish]) }
        if vegetarian { found.subtract([.seafood, .shellfish]) }

        return found
    }

    private static let keywordsByIntolerance: [FoodIntolerance: [String]] = [
        .dairy: ["milk", "cheese", "cream", "butter", "yogurt", "yoghurt", "ghee", "casein", "whey", "custard"],
        .egg: ["egg", "mayonnaise", "meringue"],
        .gluten: ["wheat", "flour", "barley", "rye", "malt", "bread", "pasta", "couscous", "semolina", "farro", "bulgur", "seitan"],
        .grain: ["rice", "oat", "corn", "quinoa", "wheat", "barley", "rye", "millet", "buckwheat", "sorghum"],
        .peanut: ["peanut", "groundnut"],
        .seafood: ["fish", "salmon", "tuna", "cod", "anchovy", "sardine", "tilapia", "haddock", "trout", "mackerel", "halibut"],
        .sesame: ["sesame", "tahini"],
        .shellfish: ["shrimp", "prawn", "crab", "lobster", "clam", "mussel", "oyster", "scallop", "squid", "calamari", "crawfish"],
        .soy: ["soy", "soya", "tofu", "edamame", "tempeh", "miso"],
        .sulfite: ["wine", "dried apricot", "raisin"],
        .treeNut: ["almond", "cashew", "walnut", "pecan", "pistachio", "hazelnut", "macadamia", "brazil nut", "pine nut", "praline"],
        .wheat: ["wheat", "flour", "bread", "pasta", "couscous", "semolina", "farro", "bulgur"],
    ]
}
