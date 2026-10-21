//
//  RawInterpretedReceiptItem.swift
//  FridgeFit
//

import Foundation

/// One receipt line as the language model interpreted it - untrusted input.
///
/// Mirrors `RawSubstitutionSuggestion`: every field stays a raw primitive,
/// because a generative model cannot be trusted to only emit values from
/// our enums, to echo a line back unchanged, or to keep a quantity it was
/// given. `ReceiptItemNormalizer` is the only thing allowed to turn this
/// into a `ReceiptIngredientCandidate`.
///
/// `originalText` is the model's echo of the line it was interpreting. It is
/// how an interpretation gets matched back to the real parsed line, and the
/// normalizer rejects any item whose echo does not correspond to a line that
/// was actually sent - which is the main defence against the model inventing
/// groceries that were never on the receipt.
nonisolated struct RawInterpretedReceiptItem: Equatable, Codable {
    let originalText: String
    let displayName: String
    let canonicalName: String
    let classification: String
    let category: String
    /// The model's proposed quantity. `0` means "not stated on the
    /// receipt". Only ever used when the deterministic parser found
    /// nothing and the number genuinely appears in the receipt text.
    let quantity: Double
    /// The model's proposed unit symbol, or an empty string for unknown.
    let unit: String

    init(
        originalText: String,
        displayName: String,
        canonicalName: String,
        classification: String,
        category: String,
        quantity: Double,
        unit: String
    ) {
        self.originalText = originalText
        self.displayName = displayName
        self.canonicalName = canonicalName
        self.classification = classification
        self.category = category
        self.quantity = quantity
        self.unit = unit
    }
}

/// Everything a `ReceiptIngredientInterpreter` returned for one receipt.
///
/// Holds raw, unvalidated interpretations only.
nonisolated struct ReceiptInterpretationResult: Equatable {
    let items: [RawInterpretedReceiptItem]

    init(items: [RawInterpretedReceiptItem]) {
        self.items = items
    }

    static let empty = ReceiptInterpretationResult(items: [])
}
