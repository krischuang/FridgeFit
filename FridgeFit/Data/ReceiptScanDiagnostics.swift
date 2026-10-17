//
//  ReceiptScanDiagnostics.swift
//  FridgeFit
//

import Foundation

/// DEBUG-only visibility into what each stage of a receipt scan produced.
///
/// A receipt scan has four places it can go wrong - OCR misread the text,
/// the parser dropped the line, the model misclassified it, or
/// canonicalization merged it into something else - and from the
/// confirmation screen alone they are indistinguishable. This prints each
/// stage so they aren't.
///
/// ## Why `print` and not `Logger`
///
/// A receipt is a record of what someone bought, where and when. `Logger`
/// writes to the unified log, which persists on the device and is
/// collectable in a sysdiagnose long after the scan. `print` goes to the
/// attached Xcode console and nowhere else.
///
/// The whole body is behind `#if DEBUG`, so in a release build these calls
/// compile away to nothing and no receipt content is written anywhere.
nonisolated enum ReceiptScanDiagnostics {
    /// Names the technology actually doing the work, so a build can be
    /// identified at a glance rather than assumed.
    static func engine(_ description: String) {
        #if DEBUG
        print("\n=== RECEIPT SCAN ENGINE ===\n\(description)")
        #endif
    }

    static func recognizedText(_ recognized: RecognizedReceiptText) {
        #if DEBUG
        print("\n=== RECEIPT OCR ===")
        print("Raw OCR lines (\(recognized.lines.count)):")
        guard !recognized.lines.isEmpty else {
            print("  (none)")
            return
        }
        for line in recognized.lines {
            let confidence = line.confidence.map { String(format: " [%.2f]", $0) } ?? ""
            print("  \(line.order + 1). \(line.text)\(confidence)")
        }
        #endif
    }

    static func parsedLines(_ lineItems: [ReceiptLineItem]) {
        #if DEBUG
        print("\n=== PARSED LINES (\(lineItems.count)) ===")
        guard !lineItems.isEmpty else {
            print("  (none - no line looked like a purchased product)")
            return
        }
        for item in lineItems {
            let price = item.price.map { String(format: "  price %.2f", $0) } ?? ""
            print("  \(item.productDescription)\(price)")
        }
        #endif
    }

    static func interpretation(_ result: ReceiptInterpretationResult) {
        #if DEBUG
        print("\n=== FOUNDATION MODEL OUTPUT (\(result.items.count)) ===")
        guard !result.items.isEmpty else {
            print("  (none)")
            return
        }
        for item in result.items {
            let quantity = item.quantity > 0
                ? "\(formatted(item.quantity)) \(item.unit.isEmpty ? "?" : item.unit)"
                : "not stated"
            print("""
                  \(item.displayName.isEmpty ? "(no name)" : item.displayName)
                    echo:           \(item.originalText)
                    classification: \(item.classification)
                    canonical:      \(item.canonicalName)
                    category:       \(item.category)
                    quantity:       \(quantity)
                """)
        }
        #endif
    }

    static func outcome(_ outcome: ReceiptScanOutcome) {
        #if DEBUG
        print("\n=== FINAL PANTRY CANDIDATES (\(outcome.pantryCandidates.count)) ===")
        if outcome.pantryCandidates.isEmpty {
            print("  (none)")
        }
        for candidate in outcome.pantryCandidates {
            print("  \(candidate.displayName)  [\(candidate.canonicalName)]  \(candidate.quantity?.formatted ?? "quantity not detected")  \(candidate.category.rawValue)")
        }

        print("\n=== EXCLUDED (\(outcome.excluded.count)) ===")
        if outcome.excluded.isEmpty {
            print("  (none)")
        }
        for candidate in outcome.excluded {
            print("  \(candidate.displayName)  → \(candidate.classification.diagnosticLabel)  (from \"\(candidate.sourceText)\")")
        }
        print("")
        #endif
    }

    #if DEBUG
    private static func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(value)
    }
    #endif
}
