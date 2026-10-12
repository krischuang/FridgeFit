//
//  SpoonacularUnitMapperTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class SpoonacularUnitMapperTests: XCTestCase {
    func test_capitalT_isTablespoon_lowercaseT_isTeaspoon() {
        XCTAssertEqual(SpoonacularUnitMapper.map("T").unit, .tablespoons)
        XCTAssertEqual(SpoonacularUnitMapper.map("t").unit, .teaspoons)
    }

    func test_commonSpellings_mapToUnits() {
        XCTAssertEqual(SpoonacularUnitMapper.map("gr").unit, .grams)
        XCTAssertEqual(SpoonacularUnitMapper.map("Kilograms").unit, .kilograms)
        XCTAssertEqual(SpoonacularUnitMapper.map("millilitres").unit, .milliliters)
        XCTAssertEqual(SpoonacularUnitMapper.map("l").unit, .liters)
        XCTAssertEqual(SpoonacularUnitMapper.map("Tbsps").unit, .tablespoons)
        XCTAssertEqual(SpoonacularUnitMapper.map("cups").unit, .cups)
        XCTAssertEqual(SpoonacularUnitMapper.map("").unit, .pieces)
    }

    func test_servings_isPiecesButUncertain() {
        let mapped = SpoonacularUnitMapper.map("servings")
        XCTAssertEqual(mapped.unit, .pieces)
        XCTAssertTrue(mapped.quantityIsUncertain)
    }

    func test_unknownUnit_returnsNil_ratherThanGuessing() {
        XCTAssertNil(SpoonacularUnitMapper.map("pinch").unit)
        XCTAssertNil(SpoonacularUnitMapper.map("can").unit)
    }
}
