//
//  MockReceiptScanning.swift
//  FridgeFit
//

import CoreGraphics
import Foundation
import ImageIO

/// Test double / preview double for `ReceiptTextRecognizer`.
///
/// Returns whatever `result` is set to, so the whole scan flow can be
/// driven from a unit test with no Vision, no camera and no device. The
/// convenience initialiser takes plain lines of text, which is how a
/// receipt fixture is actually written.
final class MockReceiptTextRecognizer: ReceiptTextRecognizer {
    var result: Result<RecognizedReceiptText, Error>
    /// Holds the call open long enough for a test to cancel it, and
    /// respects cancellation while waiting.
    var delay: Duration?

    private(set) var recognizeCallCount = 0

    init(result: Result<RecognizedReceiptText, Error> = .success(.empty), delay: Duration? = nil) {
        self.result = result
        self.delay = delay
    }


    /// Builds a recogniser that returns these lines, in this order.
    convenience init(lines: [String], confidence: Float = 0.9, delay: Duration? = nil) {
        self.init(result: .success(.init(lines: lines, confidence: confidence)), delay: delay)
    }

    func recognizeText(
        in image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> RecognizedReceiptText {
        recognizeCallCount += 1

        if let delay {
            try await Task.sleep(for: delay)
        }
        try Task.checkCancellation()

        return try result.get()
    }
}

/// Test double / preview double for `ReceiptIngredientInterpreter`.
///
/// `availability` is settable so the unavailable states - Apple
/// Intelligence off, device not supported, model still downloading - can
/// each be exercised without the hardware that produces them.
final class MockReceiptIngredientInterpreter: ReceiptIngredientInterpreter {
    var result: Result<ReceiptInterpretationResult, Error>
    var availability: AppleIntelligenceAvailability
    var delay: Duration?

    private(set) var interpretCallCount = 0
    /// What the interpreter was last asked to interpret, so a test can
    /// assert the model only ever saw cleaned text.
    private(set) var lastLineItems: [ReceiptLineItem] = []

    init(
        result: Result<ReceiptInterpretationResult, Error> = .success(.empty),
        availability: AppleIntelligenceAvailability = .available,
        delay: Duration? = nil
    ) {
        self.result = result
        self.availability = availability
        self.delay = delay
    }


    func interpret(lineItems: [ReceiptLineItem]) async throws -> ReceiptInterpretationResult {
        interpretCallCount += 1
        lastLineItems = lineItems

        if let delay {
            try await Task.sleep(for: delay)
        }
        try Task.checkCancellation()

        return try result.get()
    }
}

extension RecognizedReceiptText {
    /// Builds recognised text from plain lines, numbering them in order.
    init(lines: [String], confidence: Float = 0.9) {
        self.init(
            lines: lines.enumerated().map { index, text in
                RecognizedReceiptLine(text: text, confidence: confidence, order: index)
            }
        )
    }
}

/// A short receipt for SwiftUI previews.
///
/// Previews only - the equivalent fixture for tests lives in the test
/// target, so production code carries no expectations about any
/// particular receipt.
enum SampleReceiptPreviewData {
    static let lines = [
        "WOOLWORTHS",
        "BANANA CAVENDISH       3.42",
        "CHKN BREAST 500G       8.50",
        "MUSHROOM CUP 200G      4.00",
        "CAPS RED               2.71",
        "SALMON ATL            11.50",
        "COCA COLA              4.50",
        "DISHWASH TABLETS      12.00",
        "PAPER TOWEL            5.00",
        "TOTAL                 52.13"
    ]
}

extension ReceiptScanOutcome {
    /// Convenience for previews: a plausible scan of a grocery receipt.
    static let sampleReceipt = ReceiptScanOutcome(
        pantryCandidates: [
            ReceiptIngredientCandidate(
                displayName: "Banana",
                canonicalName: "banana",
                classification: .ingredient,
                category: .produce,
                quantity: nil,
                sourceText: "BANANA CAVENDISH 3.42",
                order: 1
            ),
            ReceiptIngredientCandidate(
                displayName: "Chicken Breast",
                canonicalName: "chicken",
                classification: .ingredient,
                category: .meat,
                quantity: ReceiptQuantity(value: 500, unit: .grams),
                sourceText: "CHKN BREAST 500G 8.50",
                order: 2
            ),
            ReceiptIngredientCandidate(
                displayName: "Cup Mushrooms",
                canonicalName: "mushroom",
                classification: .ingredient,
                category: .produce,
                quantity: ReceiptQuantity(value: 200, unit: .grams),
                sourceText: "MUSHROOM CUP 200G 4.00",
                order: 3
            ),
            ReceiptIngredientCandidate(
                displayName: "Red Capsicum",
                canonicalName: "bell_pepper",
                classification: .ingredient,
                category: .produce,
                quantity: nil,
                sourceText: "CAPS RED 2.71",
                order: 4
            ),
            ReceiptIngredientCandidate(
                displayName: "Atlantic Salmon",
                canonicalName: "salmon",
                classification: .ingredient,
                category: .meat,
                quantity: nil,
                sourceText: "SALMON ATL 11.50",
                order: 5
            )
        ],
        excluded: [
            ReceiptIngredientCandidate(
                displayName: "Coca Cola",
                canonicalName: "coca_cola",
                classification: .beverage,
                category: .other,
                quantity: nil,
                sourceText: "COCA COLA 4.50",
                order: 6
            ),
            ReceiptIngredientCandidate(
                displayName: "Dishwashing Tablets",
                canonicalName: "dishwashing_tablet",
                classification: .household,
                category: .other,
                quantity: nil,
                sourceText: "DISHWASH TABLETS 12.00",
                order: 7
            )
        ]
    )
}
