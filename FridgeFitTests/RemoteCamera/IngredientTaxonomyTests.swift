//
//  IngredientTaxonomyTests.swift
//  FridgeFitTests
//

import CoreML
import XCTest
@testable import FridgeFit

/// The vocabulary, and the in-app half of the parity guarantee.
///
/// `tools/yolo-export/verify_parity.py` checks the exported Core ML model
/// against PyTorch at build time. This checks the other seam: that the
/// vocabulary file the app reads still describes the model the app ships.
/// A mismatch there would name every box wrong while still drawing it in the
/// right place - the exact failure the whole parity exercise exists to stop.
final class IngredientTaxonomyTests: XCTestCase {

    private func loadTaxonomy() throws -> IngredientTaxonomy {
        try IngredientTaxonomy.load(in: .main)
    }

    // MARK: - Loading

    func test_theVocabularyIsBundled() throws {
        let taxonomy = try loadTaxonomy()

        XCTAssertEqual(taxonomy.modelIdentifier, "yolov8s-worldv2")
        XCTAssertGreaterThan(taxonomy.definitions.count, 100)
    }

    func test_aMissingVocabularyIsReportedNotGuessedAt() {
        XCTAssertThrowsError(try IngredientTaxonomy.load(named: "no_such_vocabulary", in: .main)) { error in
            XCTAssertEqual(error as? IngredientTaxonomy.LoadError,
                           .fileMissing(name: "no_such_vocabulary"))
        }
    }

    // MARK: - Parity with the shipped model

    /// The decisive in-app check: the bundled model's class list, in index
    /// order, must equal the bundled vocabulary.
    func test_theModelsClassOrderMatchesTheVocabulary() throws {
        let taxonomy = try loadTaxonomy()
        let url = try XCTUnwrap(
            YOLOFoodDetectionService.modelURL(
                named: IngredientDetectorFactory.ingredientModelName, in: .main
            ),
            "the ingredient model is not bundled"
        )
        let model = try MLModel(contentsOf: url)

        // Ultralytics writes the class list into creator-defined metadata as
        // a Python dict literal: {0: 'apple', 1: 'banana', …}
        let creatorDefined = try XCTUnwrap(
            model.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
        )
        let namesLiteral = try XCTUnwrap(creatorDefined["names"], "model has no class metadata")
        let modelLabels = Self.parseNames(namesLiteral)

        XCTAssertEqual(modelLabels.count, taxonomy.definitions.count,
                       "model class count differs from the vocabulary")
        for (index, definition) in taxonomy.definitions.enumerated() {
            XCTAssertEqual(modelLabels[index], definition.term,
                           "class \(index) is \(modelLabels[index]) in the model "
                           + "but \(definition.term) in the vocabulary")
        }
    }

    /// `{0: 'apple', 1: 'banana'}` -> labels in index order.
    static func parseNames(_ literal: String) -> [String] {
        var byIndex: [Int: String] = [:]
        // Entries look like `12: 'bell pepper'`; values may contain spaces
        // but not single quotes.
        let pattern = #"(\d+)\s*:\s*'([^']*)'"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(literal.startIndex..., in: literal)
        for match in regex.matches(in: literal, range: range) {
            guard
                let indexRange = Range(match.range(at: 1), in: literal),
                let valueRange = Range(match.range(at: 2), in: literal),
                let index = Int(literal[indexRange])
            else { continue }
            byIndex[index] = String(literal[valueRange])
        }
        return byIndex.sorted { $0.key < $1.key }.map(\.value)
    }

    func test_theNameParserHandlesTheUltralyticsFormat() {
        let parsed = Self.parseNames("{0: 'apple', 1: 'bell pepper', 2: 'hot dog'}")

        XCTAssertEqual(parsed, ["apple", "bell pepper", "hot dog"])
    }

    // MARK: - Coverage

    /// The brief asks for breadth across six categories, not a fruit bowl.
    func test_everyIngredientCategoryIsRepresented() throws {
        let taxonomy = try loadTaxonomy()

        for group in IngredientGroup.allCases where group.isIngredient {
            XCTAssertFalse(taxonomy.definitions(in: group).isEmpty,
                           "\(group) has no vocabulary terms")
        }
    }

    func test_coverageIsNotDominatedByFruitAndVegetables(   ) throws {
        let taxonomy = try loadTaxonomy()
        let ingredients = taxonomy.definitions.filter { $0.category.isIngredient }
        let produce = ingredients.filter { $0.category == .fruit || $0.category == .vegetable }

        // Fruit + veg are the easiest classes and would happily eat the whole
        // vocabulary; the brief explicitly asks that they do not.
        XCTAssertLessThan(Double(produce.count) / Double(ingredients.count), 0.6,
                          "produce is \(produce.count)/\(ingredients.count) of the vocabulary")
    }

    func test_theTargetIngredientsAreInTheVocabulary() throws {
        let taxonomy = try loadTaxonomy()
        // A sample from each category of the brief's target list.
        let expected = ["apple", "banana", "strawberry", "avocado",
                        "carrot", "broccoli", "mushroom", "eggplant",
                        "bacon", "sausage", "chicken breast",
                        "salmon fillet", "prawns", "crab",
                        "egg", "butter", "tofu", "milk carton",
                        "pasta", "tin can", "bag of flour"]
        for term in expected {
            XCTAssertNotNil(taxonomy.definition(forTerm: term), "\(term) missing from the vocabulary")
        }
    }

    func test_decoysExistAndAreNotIngredients() throws {
        let taxonomy = try loadTaxonomy()
        let decoys = taxonomy.definitions(in: .decoy)

        XCTAssertFalse(decoys.isEmpty, "decoys absorb non-food objects and must be present")
        for decoy in decoys {
            XCTAssertFalse(decoy.category.isIngredient)
        }
        XCTAssertNotNil(taxonomy.definition(forTerm: "plate"))
        XCTAssertEqual(taxonomy.definition(forTerm: "plate")?.category, .decoy)
    }

    func test_ingredientCountExcludesDecoys() throws {
        let taxonomy = try loadTaxonomy()

        XCTAssertEqual(taxonomy.ingredientCount,
                       taxonomy.definitions.count - taxonomy.definitions(in: .decoy).count)
        XCTAssertFalse(taxonomy.ingredientTerms.contains("plate"))
        XCTAssertTrue(taxonomy.allTerms.contains("plate"),
                      "the model must still be allowed to report decoys")
    }

    func test_termLookupIsCaseInsensitive() throws {
        let taxonomy = try loadTaxonomy()

        XCTAssertEqual(taxonomy.definition(forTerm: "APPLE")?.ingredient, "apple")
        XCTAssertEqual(taxonomy.definition(forTerm: "Bell Pepper")?.display, "Capsicum")
        XCTAssertNil(taxonomy.definition(forTerm: "unobtainium"))
    }

    // MARK: - Ambiguous classes

    /// Raw beef, lamb and pork are not separable in a photograph. The
    /// vocabulary may contain the specific terms - they help the model
    /// localise - but they must normalise to something generic.
    func test_visuallyAmbiguousMeatsCollapseToAGenericIngredient() throws {
        let taxonomy = try loadTaxonomy()

        for term in ["raw beef steak", "raw lamb", "raw pork", "lamb chop", "pork chop"] {
            let definition = try XCTUnwrap(taxonomy.definition(forTerm: term), term)
            XCTAssertTrue(definition.requiresReview, "\(term) should require review")
            XCTAssertEqual(definition.genericFallback, "red_meat", "\(term) should collapse to red_meat")
        }
    }

    func test_unambiguousIngredientsDoNotRequireReview() throws {
        let taxonomy = try loadTaxonomy()

        for term in ["apple", "banana", "carrot", "egg", "bacon"] {
            let definition = try XCTUnwrap(taxonomy.definition(forTerm: term), term)
            XCTAssertFalse(definition.requiresReview, "\(term) should not need review by class")
        }
    }

    // MARK: - Pantry mapping

    /// The hook for a future Camera → Detection → Review → Pantry flow. The
    /// Pantry's own enum is unchanged; this only maps onto it.
    func test_everyGroupMapsOntoAPantryCategory() {
        XCTAssertEqual(IngredientGroup.fruit.pantryCategory, .produce)
        XCTAssertEqual(IngredientGroup.vegetable.pantryCategory, .produce)
        XCTAssertEqual(IngredientGroup.meat.pantryCategory, .meat)
        // The Pantry has no seafood category; meat is the closest honest fit.
        XCTAssertEqual(IngredientGroup.seafood.pantryCategory, .meat)
        XCTAssertEqual(IngredientGroup.dairy.pantryCategory, .dairy)
        // Mixed group - better `other` than a guess between grain and spice.
        XCTAssertEqual(IngredientGroup.pantry.pantryCategory, .other)
    }

    func test_theExistingPantryCategoriesAreUntouched() {
        // Guards against this feature quietly reshaping the Pantry model.
        XCTAssertEqual(
            Set(IngredientCategory.allCases.map(\.rawValue)),
            ["Produce", "Dairy", "Meat", "Grain", "Spice & Condiment", "Other"]
        )
    }

    func test_everyGroupHasDisplayMetadata() {
        for group in IngredientGroup.allCases {
            XCTAssertFalse(group.displayName.isEmpty)
            XCTAssertFalse(group.symbolName.isEmpty)
        }
    }
}
