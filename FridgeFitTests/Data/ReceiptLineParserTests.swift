//
//  ReceiptLineParserTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class ReceiptLineParserTests: XCTestCase {
    private let parser = ReceiptLineParser()

    private func parse(_ lines: [String]) -> [ReceiptLineItem] {
        parser.parse(RecognizedReceiptText(lines: lines))
    }

    // MARK: - Whole receipt

    func test_parse_keepsProductLinesAndDropsReceiptFurniture() {
        let items = parse(SampleReceipt.ocrLines)

        XCTAssertEqual(items.map(\.productDescription), SampleReceipt.expectedProductDescriptions)
    }

    func test_parse_preservesReadingOrder() {
        let items = parse(SampleReceipt.ocrLines)

        XCTAssertEqual(items.map(\.order), items.map(\.order).sorted())
    }

    // MARK: - Price handling

    func test_parse_splitsTrailingPriceFromDescription() throws {
        let item = try XCTUnwrap(parse(["CHKN BREAST 500G       8.50"]).first)

        XCTAssertEqual(item.productDescription, "CHKN BREAST 500G")
        XCTAssertEqual(item.price, 8.50)
    }

    /// The weight is part of the product, the price is not.
    func test_parse_keepsWeightWhileRemovingPrice() throws {
        let item = try XCTUnwrap(parse(["MILK FULL CREAM 2L     3.10"]).first)

        XCTAssertEqual(item.productDescription, "MILK FULL CREAM 2L")
        XCTAssertEqual(item.price, 3.10)
    }

    func test_parse_handlesCurrencySymbolAndTaxFlag() throws {
        let withSymbol = try XCTUnwrap(parse(["RICE 1KG  $4.00"]).first)
        XCTAssertEqual(withSymbol.productDescription, "RICE 1KG")
        XCTAssertEqual(withSymbol.price, 4.00)

        let withFlag = try XCTUnwrap(parse(["OLIVE OIL 500ML  9.95 T"]).first)
        XCTAssertEqual(withFlag.productDescription, "OLIVE OIL 500ML")
        XCTAssertEqual(withFlag.price, 9.95)
    }

    func test_parse_leavesDescriptionIntactWhenThereIsNoPrice() throws {
        let item = try XCTUnwrap(parse(["CAPS RED"]).first)

        XCTAssertEqual(item.productDescription, "CAPS RED")
        XCTAssertNil(item.price)
    }

    /// `500G` has no decimal part, so it must never be read as money.
    func test_priceValue_rejectsWeightsAndPlainNumbers() {
        XCTAssertNil(ReceiptLineParser.priceValue(of: "500G"))
        XCTAssertNil(ReceiptLineParser.priceValue(of: "2L"))
        XCTAssertNil(ReceiptLineParser.priceValue(of: "1234"))
        XCTAssertEqual(ReceiptLineParser.priceValue(of: "12.00"), 12.00)
    }

    // MARK: - Metadata

    func test_parse_dropsStoreAndPaymentMetadata() {
        let items = parse([
            "WOOLWORTHS",
            "SUBTOTAL   51.63",
            "GST         0.50",
            "TOTAL      52.13",
            "EFTPOS     52.13",
            "CHANGE      0.00",
            "VISA ****1234",
            "THANK YOU FOR SHOPPING",
            "ABN 88 000 014 675",
            "TAX INVOICE"
        ])

        // "WOOLWORTHS" is kept on purpose: the parser can't know it is a
        // store name, and the interpreter classifies it as unknown.
        XCTAssertEqual(items.map(\.productDescription), ["WOOLWORTHS"])
    }

    func test_parse_dropsLinesWithNoLetters() {
        XCTAssertTrue(parse(["12/03/2026", "14:32", "0000 1234 5678", "   "]).isEmpty)
    }

    /// `TOTAL` is also a yoghurt brand, so it may only be treated as
    /// metadata when nothing wordlike follows it.
    func test_parse_keepsProductsThatBeginWithAnAmbiguousKeyword() {
        let items = parse([
            "TOTAL               45.67",
            "TOTAL GREEK YOGURT   6.00"
        ])

        XCTAssertEqual(items.map(\.productDescription), ["TOTAL GREEK YOGURT"])
    }

    /// Word matching, not substring matching: `CASH` must not take
    /// `CASHEWS` with it.
    func test_parse_keepsProductsWhoseWordsContainMetadataSubstrings() {
        let items = parse([
            "CASHEWS RAW 250G     7.50",
            "CARDAMOM PODS        4.20",
            "CASH                20.00"
        ])

        XCTAssertEqual(items.map(\.productDescription), ["CASHEWS RAW 250G", "CARDAMOM PODS"])
    }

    // MARK: - Line noise

    func test_parse_stripsLeadingItemCode() throws {
        let item = try XCTUnwrap(parse(["9300601234567 TASTY CHEESE 500G   9.00"]).first)

        XCTAssertEqual(item.productDescription, "TASTY CHEESE 500G")
    }

    /// A short number at the front is part of the product, not a barcode.
    func test_parse_keepsShortLeadingNumbers() throws {
        let item = try XCTUnwrap(parse(["2 LITRE MILK     3.00"]).first)

        XCTAssertEqual(item.productDescription, "2 LITRE MILK")
    }

    /// A bare multiplier line belongs to the product above it, so folding
    /// it in keeps the count available to the quantity parser.
    func test_parse_foldsMultiplierContinuationIntoPreviousLine() throws {
        let items = parse([
            "TOMATO TRUSS      6.00",
            "2 @ $3.00"
        ])

        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.productDescription, "TOMATO TRUSS")
        XCTAssertTrue(item.originalText.contains("2 @ $3.00"))
    }

    /// "2 x TOMATO" names a product, so it is not a continuation line.
    func test_parse_treatsMultiplierWithProductNameAsItsOwnLine() {
        let items = parse(["2 x TOMATO   6.00"])

        XCTAssertEqual(items.map(\.productDescription), ["2 x TOMATO"])
    }

    func test_parse_originalTextIsNeverModified() throws {
        let raw = "9300601234567 TASTY CHEESE 500G   9.00"
        let item = try XCTUnwrap(parse([raw]).first)

        XCTAssertEqual(item.originalText, raw)
        XCTAssertNotEqual(item.productDescription, raw)
    }

    // MARK: - Degenerate input

    func test_parse_returnsEmpty_forEmptyOCR() {
        XCTAssertTrue(parser.parse(.empty).isEmpty)
    }

    func test_parse_returnsEmpty_whenEveryLineIsNoise() {
        XCTAssertTrue(parse(["", "   ", "---", "***", "12.34"]).isEmpty)
    }

    func test_parse_dropsDescriptionsThatAreTooShort() {
        XCTAssertTrue(parse(["A 1.00"]).isEmpty)
    }
}
