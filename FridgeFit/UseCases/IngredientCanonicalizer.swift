//
//  IngredientCanonicalizer.swift
//  FridgeFit
//

import Foundation

/// An ingredient name resolved to a stable internal identity.
nonisolated struct CanonicalizedIngredient: Equatable {
    /// Stable, lowercase, snake_case identity used for deduplication and
    /// pantry matching. Never shown to the user.
    let canonicalName: String
    /// What the user reads. Keeps the receipt's own flavour ("Red
    /// Capsicum") rather than the canonical form ("bell_pepper").
    let displayName: String
    /// Whether `canonicalName` came from the synonym table rather than
    /// from the generic fallback. Useful in DEBUG diagnostics to see which
    /// names the table actually knows.
    let isKnown: Bool
}

/// Resolves ingredient names to a stable canonical identity.
///
/// ## The problem this solves
///
/// The same food arrives spelled several ways in one session - from the
/// receipt (`CAPS RED`), from the model (`Red Capsicum`, `capsicum`), and
/// from the pantry the user typed by hand (`Bell Pepper`). Without a single
/// identity for them, the pantry accumulates four entries for one
/// vegetable, and the duplicate check never fires.
///
/// ## How it resolves a name
///
/// A short pipeline, each step cheap and order-dependent:
///
/// 1. **Fold** - lowercase, strip diacritics, turn `_` `-` `/` into spaces,
///    drop punctuation, collapse whitespace.
/// 2. **Phrase lookup** - the whole folded phrase, then its singularized
///    form, against the synonym table. This runs *before* any words are
///    removed, which is what protects compounds: `sweet potato` is matched
///    and returned whole, so step 3 never gets the chance to strip `sweet`
///    and merge it into `potato`.
/// 3. **Descriptor removal** - drop words that modify a food without
///    changing which food it is (`red`, `fresh`, `cup`, `fillet`,
///    `atlantic`). If removing them would leave nothing, they are kept -
///    `cherry` on its own is a fruit, not a descriptor.
/// 4. **Lookup again**, then fall back to the stripped phrase in
///    snake_case.
///
/// The fallback matters: an ingredient the table has never heard of still
/// gets a stable identity, so this generalises to arbitrary groceries
/// instead of only the ones someone remembered to list.
///
/// ## Extending it
///
/// Add a row to `canonicalBySynonym` (or `protectedCompounds` for a
/// multi-word food that descriptor removal would damage). The table is
/// deliberately a short list of genuine synonyms and dialect differences -
/// it is not, and must not become, a catalogue of supermarket products.
nonisolated struct IngredientCanonicalizer {
    /// Genuine synonyms and dialect differences, folded form on the left.
    ///
    /// `pepper veggie` is here because Apple's Vision classifier emits
    /// `pepper_veggie` as a label identifier, and names in that shape
    /// reached the pantry under the previous fridge-scan flow.
    private static let canonicalBySynonym: [String: String] = [
        // Capsicum / bell pepper, the case with the most spellings.
        "capsicum": "bell_pepper",
        "bell pepper": "bell_pepper",
        "sweet pepper": "bell_pepper",
        "pepper veggie": "bell_pepper",
        "bellpepper": "bell_pepper",

        // AU / UK / US vegetable names.
        "aubergine": "eggplant",
        "courgette": "zucchini",
        "arugula": "rocket",
        "cilantro": "coriander",
        "scallion": "spring_onion",
        "green onion": "spring_onion",
        "kumara": "sweet_potato",
        "swede": "turnip",
        "silverbeet": "chard",
        "snow pea": "snow_pea",
        "mangetout": "snow_pea",

        // Salad leaves all end up as one pantry staple.
        "salad green": "lettuce",
        "salad leaf": "lettuce",
        "mixed leaf": "lettuce",
        "mesclun": "lettuce",
        "cos": "lettuce",

        // Proteins.
        "chook": "chicken",
        "shrimp": "prawn",
        "beef mince": "beef",
        "ground beef": "beef",

        // Dairy spellings.
        "yoghurt": "yogurt",
        "natural yoghurt": "yogurt",
        "greek yoghurt": "greek_yogurt",

        // Pantry staples with two spellings.
        "chickpea": "chickpea",
        "garbanzo": "chickpea"
    ]

    /// Multi-word foods whose first word is also a descriptor. Listed so
    /// phrase lookup catches them before descriptor removal can merge them
    /// into the wrong ingredient - `sweet potato` into `potato`, `green
    /// bean` into `bean`.
    private static let protectedCompounds: Set<String> = [
        "sweet potato", "spring onion", "green bean", "snow pea",
        "brussels sprout", "bok choy", "black bean", "white bean",
        "red onion", "spring water", "baby corn", "white chocolate",
        "dark chocolate", "red wine", "white wine", "green tea"
    ]

    /// Words that modify a food without changing which food it is.
    ///
    /// Conservative on purpose. Every word added here merges two names that
    /// used to be distinct, and a wrong merge is much harder for a user to
    /// notice than a missed one. Colours like `orange` are absent because
    /// they are also foods.
    private static let descriptors: Set<String> = [
        // Colour, where it is a variety rather than a different food.
        "red", "green", "yellow", "purple", "white", "brown",
        // Size and grade.
        "large", "small", "medium", "mini", "baby", "jumbo", "extra",
        "value", "family", "bulk", "loose", "prepacked", "select", "premium",
        // State and preparation.
        "fresh", "frozen", "chilled", "raw", "whole", "half", "sliced",
        "diced", "chopped", "shredded", "crushed", "peeled", "trimmed",
        "skinless", "boneless", "cooked", "dried", "lean",
        // Cuts and portions that don't change the ingredient.
        "breast", "fillet", "portion", "cutlet", "leg", "thigh", "wing",
        "drumstick", "rasher", "leaf", "head", "stick", "spear",
        // Varieties that name the same ingredient.
        "cherry", "grape", "roma", "truss", "cavendish", "atlantic",
        "button", "cup", "field", "swiss", "iceberg", "continental",
        // Marketing and provenance.
        "organic", "free", "range", "australian", "aussie", "imported",
        "homebrand", "brand", "natural", "plain",
        // Packaging.
        "pack", "packet", "pk", "bag", "bunch", "punnet", "tray", "tub",
        "bottle", "carton", "can", "tin", "jar", "box"
    ]

    /// Display names to fall back on when the model gave us nothing
    /// usable. Australian terms, because that is who this is for.
    private static let preferredDisplayNames: [String: String] = [
        "bell_pepper": "Capsicum",
        "spring_onion": "Spring Onion",
        "sweet_potato": "Sweet Potato",
        "greek_yogurt": "Greek Yogurt",
        "snow_pea": "Snow Peas",
        "green_bean": "Green Beans"
    ]

    /// Resolves a name to its canonical identity.
    ///
    /// - Parameters:
    ///   - displayName: What the item should be called on screen, usually
    ///     the interpreter's human-readable name.
    ///   - modelCanonicalName: The interpreter's own suggestion for the
    ///     canonical form, if it offered one. Treated as a hint: it is
    ///     tried first, but only wins when it resolves to a name the table
    ///     recognises, so a nonsense suggestion can't override a display
    ///     name that resolves cleanly.
    func canonicalize(displayName: String, modelCanonicalName: String? = nil) -> CanonicalizedIngredient {
        let fromModel = (modelCanonicalName?.isEmpty == false) ? Self.resolve(modelCanonicalName!) : nil
        let fromDisplay = Self.resolve(displayName)

        let resolved: (canonical: String, isKnown: Bool)? = {
            if let fromModel, fromModel.isKnown { return fromModel }
            if let fromDisplay, fromDisplay.isKnown { return fromDisplay }
            return fromModel ?? fromDisplay
        }()

        guard let resolved, !resolved.canonical.isEmpty else {
            // Nothing usable in either name. The caller drops these.
            return CanonicalizedIngredient(canonicalName: "", displayName: "", isKnown: false)
        }

        return CanonicalizedIngredient(
            canonicalName: resolved.canonical,
            displayName: Self.presentableName(displayName, canonicalName: resolved.canonical),
            isKnown: resolved.isKnown
        )
    }

    // MARK: - Resolution pipeline

    private static func resolve(_ name: String) -> (canonical: String, isKnown: Bool)? {
        let tokens = folded(name)
        guard !tokens.isEmpty else { return nil }

        let phrase = tokens.joined(separator: " ")
        if let hit = lookup(phrase) { return (hit, true) }

        let singular = tokens.map(singularized(_:))
        let singularPhrase = singular.joined(separator: " ")
        if let hit = lookup(singularPhrase) { return (hit, true) }

        // Keep the descriptors if removing them would leave nothing - a
        // name made entirely of modifiers is a food in its own right.
        let stripped = singular.filter { !descriptors.contains($0) }
        let core = stripped.isEmpty ? singular : stripped
        let corePhrase = core.joined(separator: " ")

        if let hit = lookup(corePhrase) { return (hit, true) }

        return (snakeCased(corePhrase), false)
    }

    /// Phrase lookup covering both the synonym table and the compounds that
    /// map to themselves.
    private static func lookup(_ phrase: String) -> String? {
        if let canonical = canonicalBySynonym[phrase] { return canonical }
        if protectedCompounds.contains(phrase) { return snakeCased(phrase) }
        return nil
    }

    /// Lowercases, removes diacritics and punctuation, and splits into
    /// words. `_` `-` `/` become spaces so `bell_pepper` folds the same way
    /// `bell pepper` does.
    ///
    /// Apostrophes are deleted rather than turned into spaces, so
    /// `za'atar` folds to one word and not two.
    private static func folded(_ name: String) -> [String] {
        let lowered = name
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")

        let spaced = String(lowered.map { character in
            if character == "_" || character == "-" || character == "/" { return " " }
            return character.isLetter || character.isNumber || character == " " ? character : " "
        })

        return spaced
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }
    }

    /// Enough English plural handling for food names.
    /// Delegates to the app-wide rule so receipts and pantry matching
    /// singularize identically.
    private static func singularized(_ word: String) -> String {
        IngredientNameMatching.singularized(word)
    }

    private static func snakeCased(_ phrase: String) -> String {
        phrase.components(separatedBy: " ").filter { !$0.isEmpty }.joined(separator: "_")
    }

    // MARK: - Display

    /// Cleans the model's display name for the screen, falling back to a
    /// known Australian term when the model gave us an internal-looking
    /// identifier or nothing at all.
    private static func presentableName(_ displayName: String, canonicalName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let looksInternal = trimmed.isEmpty
            || trimmed.contains("_")
            || !trimmed.contains(where: \.isLetter)

        if looksInternal {
            return preferredDisplayNames[canonicalName] ?? titleCased(canonicalName.replacingOccurrences(of: "_", with: " "))
        }
        return titleCased(trimmed)
    }

    /// Capitalises each word, matching how pantry items added by hand read
    /// ("Greek Yogurt"), while leaving deliberate mixed case alone.
    static func titleCased(_ name: String) -> String {
        name.components(separatedBy: " ")
            .filter { !$0.isEmpty }
            .map { word in
                guard let first = word.first else { return word }
                return word.allSatisfy { $0.isLowercase || !$0.isLetter }
                    ? first.uppercased() + word.dropFirst()
                    : word
            }
            .joined(separator: " ")
    }
}
