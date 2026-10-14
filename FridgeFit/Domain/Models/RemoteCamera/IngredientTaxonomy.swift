//
//  IngredientTaxonomy.swift
//  FridgeFit
//

import Foundation

/// Broad ingredient groupings, used for the UI badge and, later, for routing
/// a confirmed item into the right part of the pantry.
///
/// Deliberately coarse. The taxonomy's job is to be stable while the model
/// underneath changes; a finer hierarchy would have to be rewritten every
/// time the vocabulary moved.
nonisolated enum IngredientGroup: String, Codable, CaseIterable, Sendable {
    case fruit
    case vegetable
    case meat
    case seafood
    case dairy
    case pantry
    /// Vocabulary terms that exist only to give non-food objects somewhere to
    /// go - plates, hands, shelves. Never surfaced as an ingredient.
    case decoy

    var displayName: String {
        switch self {
        case .fruit: return "Fruit"
        case .vegetable: return "Vegetable"
        case .meat: return "Meat"
        case .seafood: return "Seafood"
        case .dairy: return "Dairy & Eggs"
        case .pantry: return "Pantry"
        case .decoy: return "Not food"
        }
    }

    var symbolName: String {
        switch self {
        case .fruit: return "apple.logo"
        case .vegetable: return "carrot"
        case .meat: return "fork.knife"
        case .seafood: return "fish"
        case .dairy: return "takeoutbag.and.cup.and.straw"
        case .pantry: return "shippingbox"
        case .decoy: return "xmark.circle"
        }
    }

    /// Whether this category should ever reach the user.
    var isIngredient: Bool { self != .decoy }

    /// The pantry category a confirmed item of this group would belong to.
    ///
    /// Deliberately a separate axis from `IngredientCategory`, which is the
    /// Pantry's own taxonomy and is not changed by this feature. Detection
    /// groups are finer in some places (fruit vs vegetable, both `produce`)
    /// and coarser in others - the Pantry has no seafood category, so
    /// seafood maps onto `meat`, and the mixed `pantry` group maps onto
    /// `other` rather than guessing between `grain` and `spice`.
    ///
    /// Nothing calls this yet: detections are candidates, and only a user
    /// confirming one should ever create a `PantryItem`.
    var pantryCategory: IngredientCategory {
        switch self {
        case .fruit, .vegetable: return .produce
        case .meat, .seafood: return .meat
        case .dairy: return .dairy
        case .pantry, .decoy: return .other
        }
    }
}

/// One vocabulary entry: what the model can say, and what it means.
///
/// `term` is the model's label; `ingredient` is the stable identifier the
/// rest of the app uses. The two differ on purpose - several terms can
/// normalise to one ingredient ("raw beef steak" and "minced beef" both
/// become `red_meat`), and swapping the model should change terms without
/// changing ingredient identifiers.
nonisolated struct IngredientDefinition: Equatable, Sendable, Codable {
    /// The vocabulary term, exactly as the model emits it.
    let term: String
    /// Stable identifier, e.g. `"red_meat"`.
    let ingredient: String
    let display: String
    let category: IngredientGroup
    /// Whether a detection of this term always needs human confirmation.
    ///
    /// Set for things the model cannot honestly distinguish - raw beef, lamb
    /// and pork look alike, and asserting a species from a photograph would
    /// be a guess dressed as a fact.
    let requiresReview: Bool
    /// An identifier to collapse to when reporting conservatively.
    let genericFallback: String?

    private enum CodingKeys: String, CodingKey {
        case term, ingredient, display, category, requiresReview, genericFallback
    }
}

/// The vocabulary, loaded from the same JSON the exporter used.
///
/// Sharing one file is what keeps Core ML class indices and the app's
/// understanding of them from drifting apart: `verify_parity.py` checks the
/// exported model's class order against this exact file, and the app reads it
/// rather than duplicating the list in Swift.
///
/// Model-independent by construction - point `modelName` at a different
/// export with a different `ingredient_vocabulary.json` and nothing else in
/// the app needs to change.
nonisolated struct IngredientTaxonomy: Sendable {
    let version: Int
    let modelIdentifier: String
    /// In vocabulary order, i.e. Core ML class-index order.
    let definitions: [IngredientDefinition]

    private let byTerm: [String: IngredientDefinition]

    init(version: Int, modelIdentifier: String, definitions: [IngredientDefinition]) {
        self.version = version
        self.modelIdentifier = modelIdentifier
        self.definitions = definitions
        self.byTerm = Dictionary(
            definitions.map { ($0.term.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    nonisolated enum LoadError: Error, Equatable, Sendable {
        case fileMissing(name: String)
        case unreadable(reason: String)

        var message: String {
            switch self {
            case .fileMissing(let name):
                return "The ingredient vocabulary (\(name).json) isn't bundled with this build."
            case .unreadable(let reason):
                return "The ingredient vocabulary couldn't be read: \(reason)"
            }
        }
    }

    private struct Document: Decodable {
        let version: Int
        let model: String
        let terms: [IngredientDefinition]
    }

    static func load(
        named name: String = "ingredient_vocabulary",
        in bundle: Bundle = .main
    ) throws -> IngredientTaxonomy {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw LoadError.fileMissing(name: name)
        }
        do {
            let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
            return IngredientTaxonomy(
                version: document.version,
                modelIdentifier: document.model,
                definitions: document.terms
            )
        } catch {
            throw LoadError.unreadable(reason: error.localizedDescription)
        }
    }

    // MARK: - Lookup

    func definition(forTerm term: String) -> IngredientDefinition? {
        byTerm[term.lowercased()]
    }

    /// Terms that should be shown to the user if detected.
    var ingredientTerms: Set<String> {
        Set(definitions.filter { $0.category.isIngredient }.map { $0.term.lowercased() })
    }

    /// Every term the model knows, including decoys.
    ///
    /// The detector must be allowed to *report* decoys - that is the whole
    /// point of them. They are dropped when normalising to ingredients.
    var allTerms: Set<String> {
        Set(definitions.map { $0.term.lowercased() })
    }

    var ingredientCount: Int {
        definitions.filter { $0.category.isIngredient }.count
    }

    func definitions(in category: IngredientGroup) -> [IngredientDefinition] {
        definitions.filter { $0.category == category }
    }

    /// Distinct ingredient display names per category, for the UI.
    func displayNames(in category: IngredientGroup) -> [String] {
        var seen = Set<String>()
        return definitions(in: category).compactMap { seen.insert($0.display).inserted ? $0.display : nil }
    }
}
