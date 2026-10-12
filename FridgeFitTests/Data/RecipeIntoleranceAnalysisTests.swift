//
//  RecipeIntoleranceAnalysisTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class RecipeIntoleranceAnalysisTests: XCTestCase {
    func test_noIngredientNames_returnsNil_unverified() {
        XCTAssertNil(RecipeIntoleranceAnalysis.intolerances(inIngredientNames: []))
        XCTAssertNil(RecipeIntoleranceAnalysis.intolerances(inIngredientNames: ["  "]))
    }

    func test_detectsKeywordsInIngredientNames() {
        let found = RecipeIntoleranceAnalysis.intolerances(inIngredientNames: ["Peanut Butter", "shrimp"])
        XCTAssertEqual(found?.contains(.peanut), true)
        XCTAssertEqual(found?.contains(.shellfish), true)
        XCTAssertEqual(found?.contains(.dairy), true, "Over-reporting is intentional for a safety filter")
    }

    func test_providerDairyFreeFlag_overridesKeywordFalsePositive() {
        let found = RecipeIntoleranceAnalysis.intolerances(inIngredientNames: ["coconut milk"], knownDairyFree: true)
        XCTAssertEqual(found, [])
    }

    func test_safeIngredients_returnEmptySet() {
        XCTAssertEqual(RecipeIntoleranceAnalysis.intolerances(inIngredientNames: ["carrot", "potato"]), [])
    }
}
