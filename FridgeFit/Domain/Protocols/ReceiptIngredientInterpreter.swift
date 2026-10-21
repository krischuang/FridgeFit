//
//  ReceiptIngredientInterpreter.swift
//  FridgeFit
//

import Foundation

/// Turns cleaned receipt product lines into candidate ingredients.
///
/// This is the only place a language model is involved in a receipt scan,
/// and it only ever sees **text**: the product descriptions that
/// `ReceiptLineParser` extracted. No image, no pixels, no photo data.
///
/// Returns untrusted `RawInterpretedReceiptItem`s only. Nothing here may
/// decide what reaches the pantry, what an item is called in canonical
/// terms, or how much of it there is - `ReceiptItemNormalizer` and
/// `IngredientCanonicalizer` do that deterministically, downstream, the same
/// way `SubstitutionService` output goes through validation before the UI
/// sees it.
nonisolated protocol ReceiptIngredientInterpreter {
    /// Whether this interpreter can run right now, in FridgeFit's terms.
    ///
    /// Read fresh on every access - the user can turn Apple Intelligence on
    /// or off, and the model can finish downloading, while the app is open.
    var availability: AppleIntelligenceAvailability { get }

    /// Interprets receipt product lines.
    ///
    /// - Throws: `ReceiptScanError`, never a provider-specific error type.
    func interpret(lineItems: [ReceiptLineItem]) async throws -> ReceiptInterpretationResult
}
