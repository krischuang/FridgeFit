//
//  SampleReceipt.swift
//  FridgeFitTests
//

import Foundation
@testable import FridgeFit

/// A representative Australian supermarket receipt, as OCR would read it.
///
/// Used to exercise the parser and the normalizer end to end against
/// something shaped like a real receipt: a store header, products with and
/// without stated quantities, abbreviations, two non-food items, and the
/// totals block at the bottom.
///
/// This is test data, not a production rule. Nothing in the app knows
/// about these particular products - the parser's metadata handling and the
/// canonicalizer's synonym table are both general, and the tests below
/// assert general behaviour that this receipt happens to exercise.
enum SampleReceipt {
    /// The lines as they come out of OCR, top to bottom.
    static let ocrLines = [
        "WOOLWORTHS",
        "ABN 88 000 014 675",
        "STORE 1234  TEL 02 9999 8888",
        "TAX INVOICE",
        "BANANA CAVENDISH       3.42",
        "CHKN BREAST 500G       8.50",
        "MUSHROOM CUP 200G      4.00",
        "CAPS RED               2.71",
        "SALMON ATL            11.50",
        "COCA COLA              4.50",
        "DISHWASH TABLETS      12.00",
        "PAPER TOWEL            5.00",
        "SUBTOTAL              51.63",
        "GST                    0.50",
        "TOTAL                 52.13",
        "EFTPOS                52.13",
        "CHANGE                 0.00",
        "THANK YOU FOR SHOPPING"
    ]

    static var recognizedText: RecognizedReceiptText {
        RecognizedReceiptText(lines: ocrLines)
    }

    /// The lines a correct parse keeps.
    ///
    /// `WOOLWORTHS` is in this list on purpose. The parser has no way to
    /// know a bare word is a store name rather than a product, so it keeps
    /// it and lets the interpreter classify it as `unknown` - which is
    /// exactly the division of labour the parser is designed around.
    static let expectedProductDescriptions = [
        "WOOLWORTHS",
        "BANANA CAVENDISH",
        "CHKN BREAST 500G",
        "MUSHROOM CUP 200G",
        "CAPS RED",
        "SALMON ATL",
        "COCA COLA",
        "DISHWASH TABLETS",
        "PAPER TOWEL"
    ]

    /// A plausible, correct interpretation of those lines, as the model
    /// would return it. Used to test everything downstream of the model
    /// without depending on the model's nondeterministic output.
    static func interpretation(
        for lineItems: [ReceiptLineItem]
    ) -> ReceiptInterpretationResult {
        let byDescription: [String: RawInterpretedReceiptItem] = [
            "WOOLWORTHS": item("WOOLWORTHS", "Woolworths", "woolworths", .unknown, .other),
            "BANANA CAVENDISH": item("BANANA CAVENDISH", "Banana", "banana", .ingredient, .produce),
            "CHKN BREAST 500G": item("CHKN BREAST 500G", "Chicken Breast", "chicken", .ingredient, .meat, 500, "g"),
            "MUSHROOM CUP 200G": item("MUSHROOM CUP 200G", "Cup Mushrooms", "mushroom", .ingredient, .produce, 200, "g"),
            "CAPS RED": item("CAPS RED", "Red Capsicum", "capsicum", .ingredient, .produce),
            "SALMON ATL": item("SALMON ATL", "Atlantic Salmon", "salmon", .ingredient, .meat),
            "COCA COLA": item("COCA COLA", "Coca Cola", "cola", .beverage, .other),
            "DISHWASH TABLETS": item("DISHWASH TABLETS", "Dishwashing Tablets", "dishwashing tablet", .household, .other),
            "PAPER TOWEL": item("PAPER TOWEL", "Paper Towel", "paper towel", .household, .other)
        ]

        return ReceiptInterpretationResult(
            items: lineItems.compactMap { byDescription[$0.productDescription] }
        )
    }

    static func item(
        _ originalText: String,
        _ displayName: String,
        _ canonicalName: String,
        _ classification: ReceiptItemClassification,
        _ category: IngredientCategory,
        _ quantity: Double = 0,
        _ unit: String = ""
    ) -> RawInterpretedReceiptItem {
        RawInterpretedReceiptItem(
            originalText: originalText,
            displayName: displayName,
            canonicalName: canonicalName,
            classification: classification.rawValue,
            category: category.rawValue,
            quantity: quantity,
            unit: unit
        )
    }
}
