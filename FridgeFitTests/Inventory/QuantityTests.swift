//
//  QuantityTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class QuantityTests: XCTestCase {

    // MARK: - Reading

    func test_normalizedAmount_isTheNumberThePantryStores() {
        XCTAssertEqual(Quantity.count(6).normalizedAmount, 6)
        XCTAssertEqual(Quantity.measure(500, unit: .grams).normalizedAmount, 500)
        // Half a bottle is half a unit, which is what recipe feasibility
        // compares against.
        XCTAssertEqual(Quantity.package(count: 1, unit: .bottle, level: .half).normalizedAmount, 0.5)
        XCTAssertEqual(Quantity.package(count: 2, unit: .pack, level: .full).normalizedAmount, 2)
    }

    func test_storageUnit_mapsPackagesOntoPieces() {
        XCTAssertEqual(Quantity.count(6).storageUnit, .pieces)
        XCTAssertEqual(Quantity.measure(1, unit: .kilograms).storageUnit, .kilograms)
        // "bottle" is not a MeasurementUnit, so the package reading is kept
        // separately on PantryItem and the amount stores as pieces.
        XCTAssertEqual(Quantity.package(count: 1, unit: .bottle, level: .half).storageUnit, .pieces)
    }

    func test_typeAndPrecision_describeTheTrackingStyle() {
        XCTAssertEqual(Quantity.count(1).type, .countable)
        XCTAssertEqual(Quantity.measure(1, unit: .grams).type, .measurable)
        XCTAssertEqual(Quantity.package(count: 1, unit: .jar, level: .full).type, .packaged)

        XCTAssertEqual(Quantity.count(1).precision, .exact)
        XCTAssertEqual(Quantity.package(count: 1, unit: .jar, level: .full).precision, .approximate)
    }

    func test_isPositive_isFalseWhenNothingIsLeft() {
        XCTAssertTrue(Quantity.count(1).isPositive)
        XCTAssertFalse(Quantity.count(0).isPositive)
        XCTAssertFalse(Quantity.measure(0, unit: .grams).isPositive)
        XCTAssertFalse(Quantity.package(count: 0, unit: .pack, level: .full).isPositive)
    }

    // MARK: - Subtracting

    func test_subtracting_reducesACount() throws {
        let result = try Quantity.count(6).subtracting(2)
        XCTAssertEqual(result, .count(4))
    }

    func test_subtracting_reducesAMeasure() throws {
        let result = try Quantity.measure(500, unit: .grams).subtracting(150)
        XCTAssertEqual(result, .measure(350, unit: .grams))
    }

    func test_subtracting_movesAPackageToTheNearestLevel() throws {
        // A full bottle minus a quarter lands on three quarters, because
        // package levels are a fixed ladder rather than a free number.
        let result = try Quantity.package(count: 1, unit: .bottle, level: .full).subtracting(0.25)
        XCTAssertEqual(result, .package(count: 1, unit: .bottle, level: .threeQuarters))
    }

    func test_subtracting_rejectsZeroOrNegativeAmounts() {
        XCTAssertThrowsError(try Quantity.count(6).subtracting(0)) { error in
            XCTAssertEqual(error as? IngredientQuantityError, .invalidAmount)
        }
        XCTAssertThrowsError(try Quantity.count(6).subtracting(-1)) { error in
            XCTAssertEqual(error as? IngredientQuantityError, .invalidAmount)
        }
    }

    func test_subtracting_refusesToUseMoreThanIsAvailable() {
        XCTAssertThrowsError(try Quantity.measure(100, unit: .grams).subtracting(150)) { error in
            XCTAssertEqual(
                error as? IngredientQuantityError,
                .amountExceedsAvailable(available: 100, unit: "g")
            )
        }
    }

    func test_subtracting_neverProducesANegativeRemainder() throws {
        // Every legal subtraction, across the range, ends at zero or above.
        for used in stride(from: 1.0, through: 6.0, by: 1.0) {
            let remaining = try Quantity.count(6).subtracting(used)
            XCTAssertGreaterThanOrEqual(remaining.normalizedAmount, 0)
        }
    }

    func test_subtracting_roundsCountsToWholeThings() throws {
        // Half an egg is not a quantity anyone records.
        let result = try Quantity.count(6).subtracting(1.4)
        XCTAssertEqual(result, .count(5))
    }

    // MARK: - Adjusting

    func test_adjusted_correctsUpwardsAndDownwards() {
        XCTAssertEqual(Quantity.count(4).adjusted(by: 2), .count(6))
        XCTAssertEqual(Quantity.measure(300, unit: .grams).adjusted(by: -100), .measure(200, unit: .grams))
    }

    func test_adjusted_clampsAtZeroRatherThanGoingNegative() {
        XCTAssertEqual(Quantity.count(1).adjusted(by: -5), .count(0))
        XCTAssertEqual(Quantity.measure(50, unit: .grams).adjusted(by: -500), .measure(0, unit: .grams))
    }

    // MARK: - Formatting

    func test_displayText_printsAmountAndUnit() {
        XCTAssertEqual(Quantity.count(6).displayText, "6 pcs")
        XCTAssertEqual(Quantity.measure(500, unit: .grams).displayText, "500 g")
        XCTAssertEqual(Quantity.measure(1.5, unit: .kilograms).displayText, "1.5 kg")
    }

    func test_displayText_printsPackageLevelsAsFractions() {
        XCTAssertEqual(Quantity.package(count: 1, unit: .bottle, level: .half).displayText, "½ bottle")
        XCTAssertEqual(Quantity.package(count: 1, unit: .pack, level: .quarter).displayText, "¼ pack")
        XCTAssertEqual(Quantity.package(count: 1, unit: .jar, level: .full).displayText, "1 jar")
        XCTAssertEqual(Quantity.package(count: 2, unit: .pack, level: .full).displayText, "2 packs")
    }

    func test_number_dropsTrailingZeroes() {
        XCTAssertEqual(QuantityFormatter.number(3), "3")
        XCTAssertEqual(QuantityFormatter.number(3.5), "3.5")
        XCTAssertEqual(QuantityFormatter.number(3.50), "3.5")
    }

    // MARK: - Codable

    func test_quantity_roundTripsThroughCodable() throws {
        let cases: [Quantity] = [
            .count(6),
            .measure(1.5, unit: .liters),
            .package(count: 2, unit: .tub, level: .threeQuarters),
        ]

        for quantity in cases {
            let data = try JSONEncoder().encode(quantity)
            let decoded = try JSONDecoder().decode(Quantity.self, from: data)
            XCTAssertEqual(decoded, quantity)
        }
    }
}
