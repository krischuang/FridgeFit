//
//  GeneratedSubstitutionMappingTests.swift
//  FridgeFitTests
//
//  Covers the translation from guided-generation output onto the untrusted
//  `RawSubstitutionSuggestion` the rest of the app already understands.
//
//  This is the part of the migration with real logic in it, and it runs
//  without a model: `GeneratedSubstitutionSuggestions` values can be built
//  by hand, which is exactly how the awkward outputs a small on-device model
//  actually produces - a quantity with no unit, an empty limitations string,
//  a suitability outside its guided range - get exercised here instead of
//  being hoped about.
//

import XCTest
@testable import FridgeFit

final class GeneratedSubstitutionMappingTests: XCTestCase {
    private func generated(
        ingredientName: String = "Greek yogurt",
        suggestedQuantity: Double = 200,
        suggestedUnit: GeneratedSubstitutionUnit = .milliliters,
        suitability: Int = 4,
        explanation: String = "Similar richness in a cold sauce.",
        limitations: String = "Can split if boiled."
    ) -> GeneratedSubstitutionSuggestion {
        GeneratedSubstitutionSuggestion(
            ingredientName: ingredientName,
            suggestedQuantity: suggestedQuantity,
            suggestedUnit: suggestedUnit,
            suitability: suitability,
            explanation: explanation,
            limitations: limitations
        )
    }

    // MARK: - Happy path

    func test_rawSuggestion_carriesEveryFieldThrough() {
        let raw = generated().rawSuggestion

        XCTAssertEqual(raw.ingredientName, "Greek yogurt")
        XCTAssertEqual(raw.suggestedQuantity, 200)
        XCTAssertEqual(raw.suggestedUnit, "ml")
        XCTAssertEqual(raw.explanation, "Similar richness in a cold sauce.")
        XCTAssertEqual(raw.limitations, "Can split if boiled.")
    }

    func test_rawSuggestions_preservesOrder_bestFirst() {
        let suggestions = GeneratedSubstitutionSuggestions(suggestions: [
            generated(ingredientName: "Greek yogurt"),
            generated(ingredientName: "Coconut milk"),
        ])

        XCTAssertEqual(suggestions.rawSuggestions.map(\.ingredientName), ["Greek yogurt", "Coconut milk"])
    }

    func test_rawSuggestions_emptyGeneration_mapsToEmptyArray() {
        XCTAssertTrue(GeneratedSubstitutionSuggestions(suggestions: []).rawSuggestions.isEmpty)
    }

    // MARK: - Quantity and unit travel together

    /// The validator can only compare a pantry amount against a suggested
    /// one when it has both a number and a unit. A number with `notStated`
    /// would otherwise be read as "200 of something".
    func test_rawSuggestion_quantityWithoutUnit_dropsBoth() {
        let raw = generated(suggestedQuantity: 200, suggestedUnit: .notStated).rawSuggestion

        XCTAssertNil(raw.suggestedQuantity)
        XCTAssertNil(raw.suggestedUnit)
    }

    /// Zero is the schema's "no specific amount" sentinel, not an amount.
    func test_rawSuggestion_zeroQuantity_dropsQuantityAndUnit() {
        let raw = generated(suggestedQuantity: 0, suggestedUnit: .milliliters).rawSuggestion

        XCTAssertNil(raw.suggestedQuantity)
        XCTAssertNil(raw.suggestedUnit)
    }

    func test_rawSuggestion_negativeQuantity_isTreatedAsNoAmount() {
        let raw = generated(suggestedQuantity: -50, suggestedUnit: .grams).rawSuggestion

        XCTAssertNil(raw.suggestedQuantity)
        XCTAssertNil(raw.suggestedUnit)
    }

    /// Every unit the schema offers has to round-trip to a symbol
    /// `MeasurementUnit` recognises, or the validator silently downgrades
    /// the suggestion to `.unsupportedUnit`.
    func test_everyGeneratedUnit_mapsToAKnownMeasurementUnitSymbol() {
        let units: [GeneratedSubstitutionUnit] = [
            .grams, .kilograms, .milliliters, .liters, .pieces, .cups, .tablespoons, .teaspoons,
        ]

        for unit in units {
            guard let symbol = generated(suggestedUnit: unit).rawSuggestion.suggestedUnit else {
                XCTFail("\(unit) produced no unit symbol")
                continue
            }
            XCTAssertNotNil(MeasurementUnit(rawValue: symbol), "\(unit) produced unknown symbol \"\(symbol)\"")
        }
    }

    func test_notStatedUnit_mapsToNoMeasurementUnit() {
        XCTAssertNil(GeneratedSubstitutionUnit.notStated.measurementUnit)
    }

    // MARK: - Limitations

    func test_rawSuggestion_emptyLimitations_becomeNil_notAnEmptyLine() {
        XCTAssertNil(generated(limitations: "").rawSuggestion.limitations)
    }

    func test_rawSuggestion_whitespaceOnlyLimitations_becomeNil() {
        XCTAssertNil(generated(limitations: "   \n  ").rawSuggestion.limitations)
    }

    func test_rawSuggestion_limitationsAreTrimmed() {
        XCTAssertEqual(generated(limitations: "  Thinner sauce.  ").rawSuggestion.limitations, "Thinner sauce.")
    }

    // MARK: - Suitability to confidence

    func test_confidence_mapsSuitabilityScaleInto0To1_monotonically() {
        let confidences = (1...5).map { GeneratedSubstitutionSuggestion.confidence(forSuitability: $0) }

        for confidence in confidences {
            XCTAssertGreaterThan(confidence, 0)
            XCTAssertLessThanOrEqual(confidence, 1)
        }
        XCTAssertEqual(confidences, confidences.sorted(), "Higher suitability must not mean lower confidence")
        XCTAssertEqual(confidences.last, 1.0)
    }

    /// A guided range is a strong hint, not a guarantee, so out-of-range
    /// values are clamped rather than passed through to the UI.
    func test_confidence_outOfRangeSuitability_isClamped() {
        XCTAssertEqual(GeneratedSubstitutionSuggestion.confidence(forSuitability: 0), GeneratedSubstitutionSuggestion.confidence(forSuitability: 1))
        XCTAssertEqual(GeneratedSubstitutionSuggestion.confidence(forSuitability: -7), GeneratedSubstitutionSuggestion.confidence(forSuitability: 1))
        XCTAssertEqual(GeneratedSubstitutionSuggestion.confidence(forSuitability: 99), 1.0)
    }

    func test_rawSuggestion_confidenceIsWithinTheDocumentedRange() throws {
        let confidence = try XCTUnwrap(generated(suitability: 3).rawSuggestion.confidence)
        XCTAssertGreaterThan(confidence, 0)
        XCTAssertLessThanOrEqual(confidence, 1)
    }

    // MARK: - Malformed output survives mapping

    /// Mapping deliberately does no filtering - a blank name is dropped
    /// downstream by `SubstitutionSuggestionValidator`, which is the single
    /// place those rules live. This pins that split so a future change
    /// doesn't start filtering in two places.
    func test_rawSuggestion_blankNameAndExplanation_areCarriedThroughForTheValidatorToReject() {
        let raw = generated(ingredientName: "   ", explanation: "").rawSuggestion

        XCTAssertEqual(raw.ingredientName, "   ")
        XCTAssertEqual(raw.explanation, "")
        XCTAssertNil(
            SubstitutionSuggestionValidator.validate(raw, against: [], dietaryRestrictions: []),
            "The validator - not the mapping - is what drops structurally invalid suggestions"
        )
    }
}
