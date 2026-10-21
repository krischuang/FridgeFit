//
//  DiscoverPantryMatchPresentationTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class DiscoverPantryMatchPresentationTests: XCTestCase {
    func test_zeroMatches_usesNeutralNoMatchesCopy() {
        let presentation = DiscoverPantryMatchPresentation(
            matchedIngredientCount: 0,
            missingIngredientCount: 4
        )

        XCTAssertEqual(presentation.state, .noMatches)
        XCTAssertEqual(presentation.title, "No pantry matches")
    }

    func test_partialMatches_roundsToNearestWholePercent() {
        let presentation = DiscoverPantryMatchPresentation(
            matchedIngredientCount: 2,
            missingIngredientCount: 1
        )

        XCTAssertEqual(presentation.state, .matched(percentage: 67))
        XCTAssertEqual(presentation.title, "67% pantry match")
    }

    func test_completeMatch_isOneHundredPercent() {
        let presentation = DiscoverPantryMatchPresentation(
            matchedIngredientCount: 3,
            missingIngredientCount: 0
        )

        XCTAssertEqual(presentation.state, .matched(percentage: 100))
        XCTAssertEqual(presentation.title, "100% pantry match")
    }

    func test_emptyIngredientData_isUnavailableRatherThanZeroPercent() {
        let presentation = DiscoverPantryMatchPresentation(
            matchedIngredientCount: 0,
            missingIngredientCount: 0
        )

        XCTAssertEqual(presentation.state, .unavailable)
        XCTAssertEqual(presentation.title, "Pantry match unavailable")
    }
}
