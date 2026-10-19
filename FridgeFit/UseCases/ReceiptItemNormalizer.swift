//
//  ReceiptItemNormalizer.swift
//  FridgeFit
//

import Foundation

/// Turns untrusted `RawInterpretedReceiptItem`s into
/// `ReceiptIngredientCandidate`s, deterministically.
///
/// The same role `SubstitutionSuggestionValidator` plays for
/// substitutions: everything a generative model says passes through here
/// before any other part of FridgeFit sees it, so the rules live in one
/// testable place instead of being spread across providers.
///
/// Rules applied, in order:
///
/// 1. **Match the item back to a real receipt line.** The model echoes the
///    line it was interpreting; an item whose echo doesn't correspond to a
///    line that was actually sent is discarded. This is the hard stop on
///    invented groceries - a model that decides a shopper probably bought
///    milk has nowhere to attach that claim.
/// 2. Drop blank or implausibly long names.
/// 3. Map classification and category strings onto their enums, falling
///    back to `.unknown` / `.other` - an unreadable classification is not
///    an ingredient.
/// 4. Canonicalize the name through `IngredientCanonicalizer`.
/// 5. Resolve the quantity, with the receipt text overriding the model.
/// 6. Collapse duplicates by canonical name.
/// 7. Split into pantry candidates and everything else.
nonisolated struct ReceiptItemNormalizer {
    /// Longer than any real product name - anything past this is a
    /// sentence, not a product.
    private static let maximumNameLength = 60

    private let canonicalizer: IngredientCanonicalizer
    private let quantityParser: ReceiptQuantityParser

    init(
        canonicalizer: IngredientCanonicalizer = IngredientCanonicalizer(),
        quantityParser: ReceiptQuantityParser = ReceiptQuantityParser()
    ) {
        self.canonicalizer = canonicalizer
        self.quantityParser = quantityParser
    }

    /// Validates a model interpretation against the lines it was given.
    ///
    /// - Parameters:
    ///   - result: What the interpreter returned.
    ///   - lineItems: The lines that were actually sent. Nothing outside
    ///     this set can become a candidate.
    func normalize(
        _ result: ReceiptInterpretationResult,
        against lineItems: [ReceiptLineItem]
    ) -> ReceiptScanOutcome {
        var remaining = Self.index(lineItems)
        var candidates: [ReceiptIngredientCandidate] = []

        for raw in result.items {
            guard let line = Self.take(matching: raw.originalText, from: &remaining) else {
                // The model echoed something that was never sent. Either it
                // paraphrased a line or it invented a product; neither is
                // safe to keep.
                continue
            }
            guard let candidate = normalize(raw, from: line) else { continue }
            candidates.append(candidate)
        }

        let ordered = candidates.sorted { $0.order < $1.order }
        let merged = collapsingDuplicates(in: ordered)

        return ReceiptScanOutcome(
            pantryCandidates: merged.filter { $0.classification.shouldAddToPantry },
            excluded: merged.filter { !$0.classification.shouldAddToPantry }
        )
    }

    // MARK: - One item

    private func normalize(
        _ raw: RawInterpretedReceiptItem,
        from line: ReceiptLineItem
    ) -> ReceiptIngredientCandidate? {
        let displayName = raw.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalSource = raw.canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty || !canonicalSource.isEmpty else { return nil }
        guard displayName.count <= Self.maximumNameLength else { return nil }

        let canonical = canonicalizer.canonicalize(
            displayName: displayName.isEmpty ? canonicalSource : displayName,
            modelCanonicalName: canonicalSource.isEmpty ? nil : canonicalSource
        )
        guard !canonical.canonicalName.isEmpty, !canonical.displayName.isEmpty else { return nil }

        return ReceiptIngredientCandidate(
            displayName: canonical.displayName,
            canonicalName: canonical.canonicalName,
            classification: ReceiptItemClassification(rawValue: raw.classification) ?? .unknown,
            category: IngredientCategory(rawValue: raw.category) ?? .other,
            quantity: resolvedQuantity(for: raw, from: line),
            sourceText: line.originalText,
            order: line.order,
            price: Self.decimalPrice(line.price)
        )
    }

    /// The parser gives prices as Double; go through a 2dp string so 8.5 ends up
    /// as exactly 8.50 and not 8.4999999.
    private static func decimalPrice(_ price: Double?) -> Decimal? {
        guard let price, price >= 0 else { return nil }
        return Decimal(string: String(format: "%.2f", price), locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Decides the quantity, preferring what is written on the receipt.
    ///
    /// The deterministic parser runs first. The model's proposal is only
    /// used when the parser found nothing *and* the number it proposed
    /// actually appears in the receipt line - which stops a confident
    /// "500 g" being attached to a line that never mentioned a weight.
    private func resolvedQuantity(
        for raw: RawInterpretedReceiptItem,
        from line: ReceiptLineItem
    ) -> ReceiptQuantity? {
        if let parsed = quantityParser.quantity(in: line.originalText) {
            return parsed
        }

        guard raw.quantity > 0,
              let unit = MeasurementUnit(rawValue: raw.unit),
              ReceiptQuantityParser.text(line.originalText, states: raw.quantity)
        else {
            return nil
        }

        return ReceiptQuantity(value: raw.quantity, unit: unit)
    }

    // MARK: - Matching echoes back to lines

    /// Folded line text, in order, so an echo can be matched tolerantly.
    private static func index(_ lineItems: [ReceiptLineItem]) -> [(key: String, line: ReceiptLineItem)] {
        lineItems.map { (key: folded($0.productDescription), line: $0) }
    }

    /// Finds and consumes the line an echo refers to.
    ///
    /// Consuming matters: a model that echoes the same line twice gets one
    /// candidate, not two. Comparison is on folded text because OCR output
    /// round-tripped through a model picks up stray spacing and
    /// punctuation differences that mean nothing.
    private static func take(
        matching echo: String,
        from remaining: inout [(key: String, line: ReceiptLineItem)]
    ) -> ReceiptLineItem? {
        let key = folded(echo)
        guard !key.isEmpty else { return nil }

        if let index = remaining.firstIndex(where: { $0.key == key }) {
            return remaining.remove(at: index).line
        }
        // A model that dropped or added a trailing token still clearly
        // means one specific line, as long as only one line contains it.
        let containing = remaining.indices.filter {
            remaining[$0].key.contains(key) || key.contains(remaining[$0].key)
        }
        guard containing.count == 1, let index = containing.first else { return nil }
        return remaining.remove(at: index).line
    }

    /// Uppercased alphanumerics only - the stable part of a receipt line.
    private static func folded(_ text: String) -> String {
        String(text.uppercased().filter { $0.isLetter || $0.isNumber })
    }

    // MARK: - Deduplication

    /// Keeps one candidate per canonical name, in receipt order.
    ///
    /// Quantities of the same unit are added together, because two lines of
    /// `CHKN BREAST 500G` really is a kilogram of chicken - that is what
    /// the receipt says. When the units differ, or only one line stated an
    /// amount, the first stated quantity is kept rather than inventing a
    /// conversion.
    private func collapsingDuplicates(
        in candidates: [ReceiptIngredientCandidate]
    ) -> [ReceiptIngredientCandidate] {
        var byCanonical: [String: ReceiptIngredientCandidate] = [:]
        var order: [String] = []

        for candidate in candidates {
            guard let existing = byCanonical[candidate.canonicalName] else {
                byCanonical[candidate.canonicalName] = candidate
                order.append(candidate.canonicalName)
                continue
            }
            byCanonical[candidate.canonicalName] = Self.merging(candidate, into: existing)
        }

        return order.compactMap { byCanonical[$0] }
    }

    private static func merging(
        _ candidate: ReceiptIngredientCandidate,
        into existing: ReceiptIngredientCandidate
    ) -> ReceiptIngredientCandidate {
        let quantity: ReceiptQuantity? = {
            switch (existing.quantity, candidate.quantity) {
            case let (existingQuantity?, candidateQuantity?) where existingQuantity.unit == candidateQuantity.unit:
                return ReceiptQuantity(value: existingQuantity.value + candidateQuantity.value, unit: existingQuantity.unit)
            case let (existingQuantity?, _):
                return existingQuantity
            case let (nil, candidateQuantity):
                return candidateQuantity
            }
        }()

        // An item is only excluded from the pantry if every line for it
        // was: one line classified as an ingredient is enough.
        let classification = existing.classification.shouldAddToPantry
            ? existing.classification
            : candidate.classification

        return ReceiptIngredientCandidate(
            id: existing.id,
            displayName: existing.displayName,
            canonicalName: existing.canonicalName,
            classification: classification,
            category: existing.category == .other ? candidate.category : existing.category,
            quantity: quantity,
            sourceText: existing.sourceText == candidate.sourceText
                ? existing.sourceText
                : "\(existing.sourceText) · \(candidate.sourceText)",
            order: existing.order,
            isAlreadyInPantry: existing.isAlreadyInPantry,
            // two lines of the same thing = paid twice. if either line had no price
            // we don't know the total, so don't pretend we do
            price: existing.price.flatMap { a in candidate.price.map { a + $0 } }
        )
    }
}
