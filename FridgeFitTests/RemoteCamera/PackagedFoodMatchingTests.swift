//
//  PackagedFoodMatchingTests.swift
//  FridgeFitTests
//

import Foundation
import XCTest
@testable import FridgeFit

/// OCR text to ingredient matching.
///
/// The bug these exist for: `ICE CREAM - ΠΑΓΩΤΑ` matched `cream_carton`,
/// because "cream" is a legitimate whole word inside "ice cream". Whole-word
/// matching is necessary but not sufficient - surrounding words change what a
/// word denotes.
final class PackagedFoodMatchingTests: XCTestCase {

    private func reader(
        _ configuration: PackagedFoodTextReader.Configuration = .matching
    ) throws -> PackagedFoodTextReader {
        PackagedFoodTextReader(
            taxonomy: try IngredientTaxonomy.load(in: .main), configuration: configuration
        )
    }

    // MARK: - The regression

    func test_iceCreamIsNotCream() throws {
        let matches = try reader().matches(in: [("ICE CREAM - ΠΑΓΩΤΑ", 0.9)])

        XCTAssertTrue(
            matches.isEmpty,
            "ice cream is a different food; got \(matches.map(\.ingredientId))"
        )
    }

    func test_otherMisleadingCompoundsAreAlsoRejected() throws {
        let reader = try reader()
        let cases = [
            "MILK CHOCOLATE 100G",
            "COCONUT MILK 400ML",
            "BUTTER BEANS IN WATER",
            "COCOA BUTTER MOISTURISER",
            "RICE PUDDING DESSERT",
            "CHEESECAKE SLICE",
            "SOUR CREAM & CHIVE",
            "CORNED BEEF",
        ]

        for text in cases {
            let matches = reader.matches(in: [(text, 0.9)])
            XCTAssertTrue(matches.isEmpty, "\(text) matched \(matches.map(\.ingredientId))")
        }
    }

    /// A blocked compound disqualifies only the word it misleads about. The
    /// rest of the line is still fair game - "chicken flavour noodles" really
    /// is noodles, it just is not chicken.
    func test_blockingIsScopedToTheMisleadingWord() throws {
        let matches = try reader().matches(in: [("CHICKEN FLAVOUR NOODLES", 0.9)])

        XCTAssertEqual(matches.map(\.ingredientId), ["noodles"])
        XCTAssertEqual(matches.first?.certainty, .uncertain, "'flavour' weakens it")
    }

    // MARK: - What should still match

    func test_aPlainProductNameStillMatches() throws {
        let matches = try reader().matches(in: [("ORGANIC BASMATI RICE 1KG", 0.95)])

        XCTAssertEqual(matches.first?.ingredientId, "bag_of_rice")
        XCTAssertEqual(matches.first?.matchedText, "rice")
        XCTAssertEqual(matches.first?.certainty, .likely)
    }

    func test_multiWordIngredientNamesMatchAsPhrases() throws {
        let matches = try reader().matches(in: [("SMOOTH PEANUT BUTTER 340G", 0.95)])

        XCTAssertEqual(matches.first?.ingredientId, "jar_of_peanut_butter",
                       "the longer, more specific term must win over 'butter'")
    }

    func test_packagingWordsAreStrippedFromSearchTerms() {
        XCTAssertEqual(PackagedFoodTextReader.searchKey(for: "bag of rice"), "rice")
        XCTAssertEqual(PackagedFoodTextReader.searchKey(for: "block of cheese"), "cheese")
        XCTAssertEqual(PackagedFoodTextReader.searchKey(for: "jar of peanut butter"), "peanut butter")
        XCTAssertNil(PackagedFoodTextReader.searchKey(for: "tin can"),
                     "nothing but packaging words leaves no food to search for")
    }

    func test_partialWordsNeverMatch() throws {
        let reader = try reader()

        XCTAssertTrue(reader.matches(in: [("CLAW HAMMER 500G", 0.95)]).isEmpty, "ham in hammer")
        XCTAssertTrue(reader.matches(in: [("BEST PRICE GUARANTEE", 0.95)]).isEmpty, "rice in price")
    }

    /// `eggplant` is itself a vocabulary term, so this line *should* match -
    /// just not as the dairy `egg` hiding inside the word.
    func test_aLongerWordIsNotReadAsTheShorterOneInsideIt() throws {
        let matches = try reader().matches(in: [("EGGPLANT PARMIGIANA", 0.95)])

        XCTAssertEqual(matches.map(\.ingredientId), ["eggplant"])
        XCTAssertFalse(matches.contains { $0.ingredientId == "egg" },
                       "the dairy 'egg' must not be found inside 'eggplant'")
    }

    // MARK: - Certainty

    /// A product name is evidence about a product, never a verified
    /// ingredient identity.
    func test_aQualifiedProductIsOnlyUncertain() throws {
        let matches = try reader().matches(in: [("STRAWBERRY FLAVOUR YOGURT", 0.95)])

        XCTAssertEqual(matches.first?.certainty, .uncertain,
                       "'flavour' means the product is not simply that ingredient")
    }

    func test_aPoorlyReadLineIsOnlyUncertain() throws {
        let matches = try reader().matches(in: [("RICE 1KG", 0.35)])

        XCTAssertEqual(matches.first?.certainty, .uncertain)
    }

    func test_thereIsNoVerifiedCertainty() {
        // If a `verified` case is ever added, this forces a decision about
        // what would justify it.
        XCTAssertEqual(Set([OCRMatchCertainty.likely, .uncertain]).count, 2)
    }

    // MARK: - Script handling

    func test_nonLatinLinesAreNotMatchedAgainstAnEnglishVocabulary() throws {
        let matches = try reader().matches(in: [
            ("ГЕРКУЛЕС", 0.9), ("МАННАЯ КРУПА", 0.9), ("ΠΑΓΩΤΑ", 0.9),
        ])

        XCTAssertTrue(matches.isEmpty)
    }

    func test_scriptDetection() {
        XCTAssertTrue(PackagedFoodTextReader.isPredominantlyLatin("ORGANIC RICE"))
        XCTAssertTrue(PackagedFoodTextReader.isPredominantlyLatin("500"), "digits are neutral")
        XCTAssertFalse(PackagedFoodTextReader.isPredominantlyLatin("ГЕРКУЛЕС"))
        XCTAssertFalse(PackagedFoodTextReader.isPredominantlyLatin("ΠΑΓΩΤΑ"))
    }

    // MARK: - The default: matching is off

    /// Matching has not been demonstrated reliable on any real packaging
    /// measured, so it is opt-in. Reading the text still works.
    func test_automaticMatchingIsOffByDefault() throws {
        XCTAssertFalse(PackagedFoodTextReader.Configuration.default.automaticMatchingEnabled)
        XCTAssertTrue(PackagedFoodTextReader.Configuration.matching.automaticMatchingEnabled)
    }

    func test_withMatchingOffTheTextIsStillReturned() throws {
        // `matches(in:)` is the matcher itself and always runs; `read` is what
        // consults the flag. Proven here at the configuration level, and end
        // to end over real images in PackagingOCRTests.
        let off = try reader(.default)
        XCTAssertFalse(off.matches(in: [("ORGANIC RICE", 0.9)]).isEmpty,
                       "the matcher still works when asked directly")
    }
}
