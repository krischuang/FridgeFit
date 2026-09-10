//
//  MeasurementUnitConversionTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class MeasurementUnitConversionTests: XCTestCase {
    func test_convert_sameUnit_returnsQuantityUnchanged() {
        XCTAssertEqual(MeasurementUnit.convert(quantity: 500, from: .grams, to: .grams), 500)
    }

    func test_convert_gramsToKilograms() {
        XCTAssertEqual(MeasurementUnit.convert(quantity: 500, from: .grams, to: .kilograms), 0.5)
    }

    func test_convert_kilogramsToGrams() {
        XCTAssertEqual(MeasurementUnit.convert(quantity: 0.5, from: .kilograms, to: .grams), 500)
    }

    func test_convert_millilitersToLiters() {
        XCTAssertEqual(MeasurementUnit.convert(quantity: 750, from: .milliliters, to: .liters), 0.75)
    }

    func test_convert_litersToMilliliters() {
        XCTAssertEqual(MeasurementUnit.convert(quantity: 1, from: .liters, to: .milliliters), 1000)
    }

    func test_convert_returnsNil_forIncompatibleDimensions() {
        XCTAssertNil(MeasurementUnit.convert(quantity: 500, from: .grams, to: .milliliters))
        XCTAssertNil(MeasurementUnit.convert(quantity: 500, from: .milliliters, to: .grams))
    }

    func test_convert_returnsNil_forUnsupportedUnitPairs() {
        // Pieces has no conversion partner - only matches itself.
        XCTAssertNil(MeasurementUnit.convert(quantity: 2, from: .pieces, to: .grams))
        // Cups/tbsp/tsp aren't modeled as exact ratios in this phase.
        XCTAssertNil(MeasurementUnit.convert(quantity: 1, from: .cups, to: .tablespoons))
    }
}
