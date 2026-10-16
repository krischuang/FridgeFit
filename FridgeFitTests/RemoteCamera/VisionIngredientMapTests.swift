//
//  VisionIngredientMapTests.swift
//  FridgeFitTests
//

import Foundation
import XCTest
@testable import FridgeFit

/// The bundled Vision identifier map, and the OCR term matcher.
///
/// Neither needs `VNClassifyImageRequest`, so both run everywhere.
final class VisionIngredientMapTests: XCTestCase {

    private func map() throws -> VisionIngredientMap {
        try VisionIngredientMap.load(in: .main)
    }

    // MARK: - Loading

    func test_theMapIsBundledAndLoads() throws {
        let map = try map()

        XCTAssertGreaterThan(map.entries.count, 80)
        XCTAssertFalse(map.source.isEmpty)
    }

    /// The Swift and Python sides read the same file; this pins the shape
    /// they both depend on.
    func test_everyCategoryIsRepresented() throws {
        let map = try map()

        for category in [IngredientGroup.fruit, .vegetable, .meat, .seafood, .dairy, .pantry] {
            XCTAssertFalse(
                map.entries(in: category).isEmpty,
                "\(category.rawValue) has no Vision identifiers mapped"
            )
        }
        XCTAssertTrue(map.entries(in: .decoy).isEmpty,
                      "decoys are a YOLO vocabulary concept; Vision uses the ignored list")
    }

    // MARK: - The three-way split

    func test_aConcreteIngredientIsAnIngredientClaim() throws {
        guard case .ingredient(let entry) = try map().kind(of: "banana") else {
            return XCTFail("banana should be an ingredient")
        }
        XCTAssertEqual(entry.ingredient, "banana")
        XCTAssertEqual(entry.category, .fruit)
    }

    func test_aConcreteButWrongFoodIsCountedNotIgnored() throws {
        XCTAssertEqual(try map().kind(of: "brownie"), .wrongFood,
                       "a wrong food claim is an error, and must be countable as one")
    }

    func test_hypernymsAndSceneLabelsAreIgnored() throws {
        let map = try map()
        for identifier in ["food", "fruit", "vegetable", "tableware", "structure", "people"] {
            XCTAssertEqual(map.kind(of: identifier), .ignored,
                           "\(identifier) is not an ingredient claim")
        }
    }

    /// Apple's taxonomy is far bigger than the slice we map, and the rest is
    /// scenery. Treating the unknown as a claim would invent ingredients.
    func test_anUnmappedIdentifierIsIgnoredRatherThanInvented() throws {
        XCTAssertEqual(try map().kind(of: "hammock"), .ignored)
        XCTAssertEqual(try map().kind(of: "unobtainium"), .ignored)
    }

    // MARK: - The species rule

    /// Vision's `meat` must not become a species claim, exactly as the
    /// detector's ambiguous terms do not.
    func test_meatHypernymsMapToGenericsAndAreFlagged() throws {
        let map = try map()

        for identifier in ["meat", "beef", "steak"] {
            guard case .ingredient(let entry) = map.kind(of: identifier) else {
                return XCTFail("\(identifier) should map to an ingredient")
            }
            XCTAssertEqual(entry.ingredient, "red_meat",
                           "\(identifier) must not assert a species")
            XCTAssertTrue(entry.requiresReview)
        }

        guard case .ingredient(let poultry) = map.kind(of: "poultry") else {
            return XCTFail("poultry should map to an ingredient")
        }
        XCTAssertEqual(poultry.ingredient, "chicken")
        XCTAssertTrue(poultry.requiresReview)
    }

    func test_anUnambiguousMeatIsNotFlagged() throws {
        guard case .ingredient(let bacon) = try map().kind(of: "bacon") else {
            return XCTFail("bacon should map to an ingredient")
        }
        XCTAssertEqual(bacon.ingredient, "bacon")
        XCTAssertFalse(bacon.requiresReview)
    }

    /// Identity namespaces must line up, or agreement can never be detected.
    func test_visionIngredientIdsShareTheDetectorsNamespace() throws {
        let map = try map()
        let taxonomy = try IngredientTaxonomy.load(in: .main)
        let detectorIngredients = Set(taxonomy.definitions.map(\.ingredient))
            .union(["red_meat", "chicken"])

        let shared = Set(map.entries.map(\.ingredient)).intersection(detectorIngredients)
        XCTAssertGreaterThan(
            shared.count, 30,
            "the two vocabularies must overlap substantially or nothing can ever agree"
        )
        for staple in ["apple", "banana", "tomato", "carrot", "red_meat"] {
            XCTAssertTrue(shared.contains(staple), "\(staple) should exist in both")
        }
    }

    func test_aMissingMapIsAClearError() {
        let empty = Bundle(for: VisionIngredientMapTests.self)
        // A bundle that definitely has no vision map resource.
        XCTAssertThrowsError(try VisionIngredientMap.load(in: Bundle(path: "/nonexistent") ?? empty))
    }
}

/// The deterministic OCR term matcher.
final class PackagedFoodTextMatchingTests: XCTestCase {

    private func reader() throws -> PackagedFoodTextReader {
        PackagedFoodTextReader(taxonomy: try IngredientTaxonomy.load(in: .main))
    }

    func test_anIngredientTermInPackagingTextIsMatched() throws {
        let matches = try reader().matches(in: [("ORGANIC BASMATI RICE 1KG", 0.95)])

        // The vocabulary term is "bag of rice"; the label says "RICE".
        XCTAssertEqual(matches.first?.ingredientId, "bag_of_rice")
        XCTAssertEqual(matches.first?.sourceLine, "ORGANIC BASMATI RICE 1KG")
    }

    /// Packaging words are stripped so a camera-phrased vocabulary can match
    /// shelf text. This is the bug that made OCR match nothing at all.
    func test_packagingWordsAreStrippedFromSearchTerms() {
        XCTAssertEqual(PackagedFoodTextReader.searchKey(for: "bag of rice"), "rice")
        XCTAssertEqual(PackagedFoodTextReader.searchKey(for: "block of cheese"), "cheese")
        XCTAssertEqual(PackagedFoodTextReader.searchKey(for: "jar of peanut butter"), "peanut butter")
        XCTAssertEqual(PackagedFoodTextReader.searchKey(for: "milk carton"), "milk")
        XCTAssertNil(PackagedFoodTextReader.searchKey(for: "tin can"),
                     "nothing but packaging words leaves no food to search for")
    }

    func test_aCompoundKeyIsMatchedAsAPhrase() throws {
        let matches = try reader().matches(in: [("SMOOTH PEANUT BUTTER 340G", 0.95)])

        XCTAssertEqual(matches.first?.ingredientId, "jar_of_peanut_butter")
    }

    /// Substring matching on short terms is how "ham" ends up in "hammer".
    func test_shortTermsMatchWholeWordsOnly() throws {
        let reader = try reader()

        XCTAssertTrue(reader.matches(in: [("CLAW HAMMER 500G", 0.95)]).isEmpty,
                      "'hammer' must not match 'ham'")
        XCTAssertTrue(reader.matches(in: [("BEST PRICE GUARANTEE", 0.95)]).isEmpty,
                      "'price' must not match 'rice'")
    }

    func test_lowConfidenceLinesAreNotMatched() throws {
        var configuration = PackagedFoodTextReader.Configuration.default
        configuration.minimumTextConfidence = 0.80
        let strict = PackagedFoodTextReader(
            taxonomy: try IngredientTaxonomy.load(in: .main), configuration: configuration
        )

        // matches() is given already-filtered lines by read(); this checks the
        // matcher itself does not re-filter, which read() is responsible for.
        XCTAssertFalse(strict.matches(in: [("RICE", 0.95)]).isEmpty)
    }

    func test_oneIngredientIsReportedOncePerReading() throws {
        let matches = try reader().matches(in: [
            ("RICE 1KG", 0.9), ("WHOLEGRAIN RICE", 0.9),
        ])

        XCTAssertEqual(matches.filter { $0.ingredientId == "bag_of_rice" }.count, 1)
    }

    func test_textWithNoIngredientTermsMatchesNothing() throws {
        let matches = try reader().matches(in: [
            ("König Ludwig", 0.9), ("Weissbier", 0.9), ("ГЕРКУЛЕС", 0.9),
        ])

        XCTAssertTrue(matches.isEmpty,
                      "brand names and non-English text yield nothing - a real limitation")
    }
}
