//
//  ReceiptQuantityParserTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class ReceiptQuantityParserTests: XCTestCase {
    private let parser = ReceiptQuantityParser()

    private func quantity(_ text: String) -> ReceiptQuantity? {
        parser.quantity(in: text)
    }

    // MARK: - Weights and volumes

    func test_quantity_readsGramsAttachedToNumber() {
        XCTAssertEqual(quantity("CHKN BREAST 500G 8.50"), ReceiptQuantity(value: 500, unit: .grams))
    }

    func test_quantity_readsKilogramsWithDecimal() {
        XCTAssertEqual(quantity("BANANA CAVENDISH 1.253KG"), ReceiptQuantity(value: 1.253, unit: .kilograms))
        XCTAssertEqual(quantity("BEEF MINCE 1.25KG"), ReceiptQuantity(value: 1.25, unit: .kilograms))
    }

    func test_quantity_readsLitresAndMillilitres() {
        XCTAssertEqual(quantity("MILK 2L"), ReceiptQuantity(value: 2, unit: .liters))
        XCTAssertEqual(quantity("JUICE 600ML"), ReceiptQuantity(value: 600, unit: .milliliters))
    }

    func test_quantity_readsUnitSeparatedByASpace() {
        XCTAssertEqual(quantity("RICE 500 g"), ReceiptQuantity(value: 500, unit: .grams))
    }

    func test_quantity_isCaseInsensitive() {
        XCTAssertEqual(quantity("rice 500g"), ReceiptQuantity(value: 500, unit: .grams))
        XCTAssertEqual(quantity("RICE 500G"), ReceiptQuantity(value: 500, unit: .grams))
    }

    // MARK: - Nothing stated

    /// The headline behaviour: no quantity on the line means no quantity,
    /// not a default of one.
    func test_quantity_returnsNil_whenTheLineStatesNoAmount() {
        XCTAssertNil(quantity("MUSHROOM CUP"))
        XCTAssertNil(quantity("CAPS RED"))
        XCTAssertNil(quantity("SALMON ATL"))
    }

    /// A price is not a quantity.
    func test_quantity_ignoresPrices() {
        XCTAssertNil(quantity("CAPS RED 2.71"))
        XCTAssertNil(quantity("DISHWASH TABLETS 12.00"))
    }

    /// A bare leading number is as likely to be a line number as a count,
    /// so it is deliberately not read as a quantity.
    func test_quantity_ignoresBareLeadingNumbers() {
        XCTAssertNil(quantity("2 TOMATOES"))
    }

    // MARK: - Counts

    func test_quantity_readsMultiplierAsACountOfPieces() {
        XCTAssertEqual(quantity("TOMATO TRUSS 6.00 2 @ $3.00"), ReceiptQuantity(value: 2, unit: .pieces))
        XCTAssertEqual(quantity("YOGHURT 3 x 1.50"), ReceiptQuantity(value: 3, unit: .pieces))
    }

    /// A stated weight is more useful than a pack count, so it wins.
    func test_quantity_prefersWeightOverCount() {
        XCTAssertEqual(
            quantity("CHKN BREAST 500G 2 @ $8.50"),
            ReceiptQuantity(value: 500, unit: .grams)
        )
    }

    // MARK: - Number scanning

    func test_splitLeadingNumber_separatesValueFromSuffix() {
        let withUnit = ReceiptQuantityParser.splitLeadingNumber("1.25KG")
        XCTAssertEqual(withUnit.value, 1.25)
        XCTAssertEqual(withUnit.remainder, "KG")

        let plain = ReceiptQuantityParser.splitLeadingNumber("500")
        XCTAssertEqual(plain.value, 500)
        XCTAssertEqual(plain.remainder, "")

        let word = ReceiptQuantityParser.splitLeadingNumber("CHKN")
        XCTAssertNil(word.value)
        XCTAssertEqual(word.remainder, "CHKN")
    }

    /// A trailing full stop ends the number rather than joining it.
    func test_splitLeadingNumber_doesNotSwallowTrailingPunctuation() {
        let result = ReceiptQuantityParser.splitLeadingNumber("500.")
        XCTAssertEqual(result.value, 500)
        XCTAssertEqual(result.remainder, ".")
    }

    // MARK: - Cross-checking a model's proposal

    func test_textStates_recognisesNumbersThatAppearInTheLine() {
        XCTAssertTrue(ReceiptQuantityParser.text("CHKN BREAST 500G", states: 500))
        XCTAssertTrue(ReceiptQuantityParser.text("BANANA 1.25KG", states: 1.25))
    }

    func test_textStates_rejectsNumbersTheLineNeverMentions() {
        XCTAssertFalse(ReceiptQuantityParser.text("CAPS RED", states: 500))
        XCTAssertFalse(ReceiptQuantityParser.text("MUSHROOM CUP", states: 1))
    }
}
