//
//  VisionIngredientMap.swift
//  FridgeFit
//

import Foundation

/// What one of Apple's 1,303 classification identifiers means to FridgeFit.
nonisolated struct VisionIngredientEntry: Equatable, Sendable, Codable {
    /// The identifier `VNClassifyImageRequest` emits, e.g. `"oranges"`.
    let identifier: String
    /// Stable ingredient identity, e.g. `"orange"`. Shares the namespace with
    /// `IngredientDefinition.ingredient`, so a YOLO term and a Vision
    /// identifier that mean the same thing resolve to the same string - which
    /// is what makes agreement between the two detectable at all.
    let ingredient: String
    let display: String
    let category: IngredientGroup
    /// True for hypernyms that must never be read as a species claim:
    /// `meat`, `beef`, `steak`, `poultry`. Mirrors the `genericFallback`
    /// rule in `IngredientNormalizer`.
    let requiresReview: Bool
}

/// How a Vision identifier should be treated.
nonisolated enum VisionIdentifierKind: Equatable, Sendable {
    /// A concrete ingredient claim.
    case ingredient(VisionIngredientEntry)
    /// A concrete *food* claim that is not one of our ingredients -
    /// "brownie", "guacamole". Never surfaced; counted as an error when
    /// scoring, because this is where confidently-wrong answers live.
    case wrongFood
    /// A hypernym or scene label - "food", "fruit", "tableware", "people".
    /// Neither a claim nor an error. The direct analogue of the decoy terms
    /// in the YOLO-World vocabulary.
    case ignored
}

/// The Vision identifier to ingredient mapping, loaded from the bundle.
///
/// The JSON is generated once and lives at
/// `tools/vision-eval/vision_ingredient_map.json`; the copy in
/// `FridgeFit/Resources/` is the same file. `score_vision.py` reads the
/// original, this type reads the copy, so the Swift pipeline and the Python
/// evaluation cannot drift apart in what they believe an identifier means.
///
/// Why a map at all: Apple's taxonomy is hierarchical and multi-label, built
/// for general photo understanding, not for a fridge. A single image yields
/// `food`, `fruit`, `banana`, `structure` and `tableware` together. Without
/// this three-way split, a scene label would be scored as an ingredient
/// claim, which is meaningless in both directions.
nonisolated struct VisionIngredientMap: Sendable {

    nonisolated enum LoadError: LocalizedError, Equatable {
        case resourceMissing(name: String)
        case malformed(reason: String)

        var message: String {
            switch self {
            case .resourceMissing(let name):
                return "The Vision ingredient map '\(name).json' is missing from the app bundle."
            case .malformed(let reason):
                return "The Vision ingredient map could not be read: \(reason)"
            }
        }

        var errorDescription: String? { message }
    }

    private struct Document: Decodable {
        let version: Int
        let source: String
        let ingredients: [VisionIngredientEntry]
        let wrongFood: [String]
        let ignored: [String]
    }

    static let resourceName = "vision_ingredient_map"

    let version: Int
    /// Human-readable description of which Vision revision this was built
    /// against, for diagnostics.
    let source: String
    let entries: [VisionIngredientEntry]

    private let byIdentifier: [String: VisionIngredientEntry]
    private let wrongFood: Set<String>
    private let ignored: Set<String>

    init(version: Int, source: String, entries: [VisionIngredientEntry],
         wrongFood: Set<String>, ignored: Set<String>) {
        self.version = version
        self.source = source
        self.entries = entries
        self.byIdentifier = Dictionary(entries.map { ($0.identifier, $0) }) { first, _ in first }
        self.wrongFood = wrongFood
        self.ignored = ignored
    }

    static func load(in bundle: Bundle = .main) throws -> VisionIngredientMap {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw LoadError.resourceMissing(name: resourceName)
        }
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: try Data(contentsOf: url))
        } catch {
            throw LoadError.malformed(reason: error.localizedDescription)
        }
        guard !document.ingredients.isEmpty else {
            throw LoadError.malformed(reason: "no ingredient entries")
        }
        return VisionIngredientMap(
            version: document.version,
            source: document.source,
            entries: document.ingredients,
            wrongFood: Set(document.wrongFood),
            ignored: Set(document.ignored)
        )
    }

    /// How to treat one identifier.
    ///
    /// Unknown identifiers are `.ignored`. Apple's taxonomy is far larger
    /// than the slice we map, and the rest is overwhelmingly scenery -
    /// "canyon", "hamster", "hammock". Treating an unmapped identifier as a
    /// claim would invent ingredients the model never asserted.
    func kind(of identifier: String) -> VisionIdentifierKind {
        if let entry = byIdentifier[identifier] { return .ingredient(entry) }
        if wrongFood.contains(identifier) { return .wrongFood }
        return .ignored
    }

    func entry(for identifier: String) -> VisionIngredientEntry? {
        byIdentifier[identifier]
    }

    var ingredientCount: Int { Set(entries.map(\.ingredient)).count }

    func entries(in category: IngredientGroup) -> [VisionIngredientEntry] {
        entries.filter { $0.category == category }
    }
}
