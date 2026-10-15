//
//  RecipeIntoleranceAnalysis.swift
//  FridgeFit
//

import Foundation

/// Derives which intolerances a recipe contains from its ingredient names.
///
/// Deliberately best-effort keyword matching that errs towards
/// *over*-reporting: for an allergen filter, a false positive is a missed
/// meal; a false negative is a hospital visit. Returns `nil` when there are
/// no names to analyse - callers treat that as unverified, and
/// `FindOnlineRecipesFromPantryUseCase` drops unverified recipes for anyone
/// with an intolerance set.
///
/// ## Why no provider flags are consulted
///
/// The source branch passed Spoonacular's own `glutenFree`, `dairyFree`,
/// `vegan` and `vegetarian` booleans in and used them to *remove* detected
/// allergens - a positive provider claim overriding FridgeFit's own
/// uncertainty. That inverted the safety bias of everything else here, and
/// for gluten it asserted exactly the `.productProvenance` claim
/// `DietaryRestriction` says cannot be made from recipe data. Those
/// parameters are gone, so no provider boolean can clear an allergen. The
/// only thing that clears a keyword hit now is a compositional fact about
/// the ingredient itself (see `excludedPhrases`).
///
/// ## Why matching is by word, not substring
///
/// The source matched with `String.contains`, which reports aubergine as
/// egg ("eggplant"), butternut squash as dairy ("butternut") and crabapple
/// as shellfish ("crabapple"). Those are not cautious readings, they are
/// wrong ones, and a filter that hides half the catalogue for made-up
/// reasons teaches people to stop trusting it. Matching whole words keeps
/// the caution where it belongs: "coconut milk" still reports dairy unless
/// an explicit compositional exclusion says otherwise.
nonisolated enum RecipeIntoleranceAnalysis {

    /// - Parameter names: the recipe's ingredient names, as the provider
    ///   reported them.
    /// - Returns: every intolerance found, or `nil` when there was nothing
    ///   to analyse - which callers must treat as unverified, not as safe.
    static func intolerances(inIngredientNames names: [String]) -> Set<FoodIntolerance>? {
        let cleaned = names
            .map(normalized)
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }

        var found: Set<FoodIntolerance> = []
        for intolerance in FoodIntolerance.allCases {
            guard let keywords = keywordsByIntolerance[intolerance] else { continue }
            let exclusions = excludedPhrases[intolerance] ?? []
            for name in cleaned {
                guard !exclusions.contains(where: { name.contains($0) }) else { continue }
                if matches(keywords: keywords, in: name) {
                    found.insert(intolerance)
                    break
                }
            }
        }
        return found
    }

    /// Lowercased, with every non-letter run collapsed to a single space, so
    /// "All-Purpose Flour" and "all purpose flour" tokenise identically and
    /// "2% milk" still yields the word "milk".
    static func normalized(_ name: String) -> String {
        let lowered = name.lowercased()
        let spaced = lowered.map { $0.isLetter ? $0 : " " }
        return String(spaced)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// Whether any keyword appears in `name`. Single-word keywords must match
    /// a whole word (allowing a simple plural); multi-word keywords are
    /// matched as a phrase.
    private static func matches(keywords: [String], in name: String) -> Bool {
        let words = name.split(separator: " ").map(String.init)
        let stems = Set(words.flatMap { word -> [String] in
            var forms = [word]
            if word.hasSuffix("es"), word.count > 3 { forms.append(String(word.dropLast(2))) }
            if word.hasSuffix("s"), word.count > 2 { forms.append(String(word.dropLast(1))) }
            return forms
        })

        for keyword in keywords {
            if keyword.contains(" ") {
                if name.contains(keyword) { return true }
            } else if stems.contains(keyword) {
                return true
            }
        }
        return false
    }

    /// Compositional facts that rule a keyword out for a specific ingredient.
    ///
    /// Every entry is a statement about what the ingredient *is* - almond
    /// milk is not dairy, peanut butter is not dairy - and is covered by a
    /// test. This is the only mechanism that removes a detected allergen,
    /// and it is deliberately not extensible by provider data.
    static let excludedPhrases: [FoodIntolerance: [String]] = [
        .dairy: [
            "coconut milk", "coconut cream", "coconut butter",
            "almond milk", "almond butter", "soy milk", "soya milk",
            "oat milk", "rice milk", "cashew milk", "cashew butter",
            "hemp milk", "nut butter", "peanut butter", "cocoa butter",
            "shea butter", "apple butter", "sunflower butter", "soy cream",
        ],
        .wheat: [
            "almond flour", "coconut flour", "rice flour", "chickpea flour",
            "corn flour", "tapioca flour", "oat flour", "buckwheat flour",
        ],
    ]

    static let keywordsByIntolerance: [FoodIntolerance: [String]] = [
        .dairy: [
            "milk", "buttermilk", "cheese", "cheddar", "mozzarella", "parmesan",
            "parmigiano", "feta", "ricotta", "gouda", "brie", "mascarpone",
            "halloumi", "paneer", "cream", "creme", "butter", "ghee",
            "yogurt", "yoghurt", "casein", "whey", "custard",
        ],
        .egg: ["egg", "mayonnaise", "mayo", "meringue", "aioli"],
        .gluten: [
            "wheat", "flour", "barley", "rye", "malt", "bread", "breadcrumb",
            "breadcrumbs", "panko", "pasta", "spaghetti", "macaroni", "noodle",
            "couscous", "semolina", "farro", "bulgur", "seitan", "cracker",
            "orzo", "cookie", "biscuit",
        ],
        .grain: [
            "rice", "oat", "corn", "cornstarch", "cornmeal", "polenta",
            "quinoa", "wheat", "barley", "rye", "millet", "buckwheat",
            "sorghum", "spelt", "farro", "bulgur", "semolina", "couscous",
        ],
        .peanut: ["peanut", "groundnut"],
        .seafood: [
            "fish", "salmon", "tuna", "cod", "anchovy", "anchovies", "sardine",
            "tilapia", "haddock", "trout", "mackerel", "halibut", "bass",
            "snapper", "pollock", "herring", "caviar",
        ],
        .sesame: ["sesame", "tahini"],
        .shellfish: [
            "shellfish", "shrimp", "prawn", "crab", "lobster", "clam",
            "mussel", "oyster", "scallop", "squid", "calamari", "crawfish",
            "crayfish", "langoustine",
        ],
        .soy: ["soy", "soya", "soybean", "tofu", "edamame", "tempeh", "miso", "tamari"],
        .sulfite: ["wine", "dried apricot", "dried apricots", "raisin", "sultana"],
        .treeNut: [
            "almond", "cashew", "walnut", "pecan", "pistachio", "hazelnut",
            "macadamia", "brazil nut", "pine nut", "praline", "marzipan",
            "nutella",
        ],
        .wheat: [
            "wheat", "flour", "bread", "breadcrumb", "breadcrumbs", "panko",
            "pasta", "spaghetti", "macaroni", "couscous", "semolina", "farro",
            "bulgur", "orzo",
        ],
    ]
}
