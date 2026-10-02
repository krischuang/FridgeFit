//
//  ReceiptQuantityParser.swift
//  FridgeFit
//

import Foundation

/// Reads a quantity out of a receipt line, or decides there isn't one.
///
/// ## Why this is deterministic and not the model's job
///
/// A quantity is the one part of a receipt line that is written down
/// exactly. `CHKN BREAST 500G` contains the number 500 and the unit `g`;
/// there is nothing to infer, and a language model asked to "extract the
/// quantity" can quietly round, convert units, or supply a plausible
/// number for a line that never had one. Scanning the characters cannot do
/// any of those things.
///
/// The interpreter still proposes a quantity, but
/// `ReceiptItemNormalizer` only accepts it when this parser found nothing
/// *and* the number it proposed actually appears in the receipt text. The
/// model may suggest; the text decides.
///
/// ## Returning nil is a real answer
///
/// `MUSHROOM CUP` has no quantity. The honest result is `nil`, which the
/// UI shows as "quantity not detected" and asks the user to fill in. The
/// previous fridge-scan flow defaulted to `1 pcs`, which looks like
/// information but is a guess the user has to notice to correct.
struct ReceiptQuantityParser {
    /// Unit suffixes as they appear on receipts, mapped onto the pantry's
    /// fixed unit set. Uppercased keys; lookups uppercase the input.
    private static let unitsBySuffix: [String: MeasurementUnit] = [
        "G": .grams, "GM": .grams, "GMS": .grams, "GR": .grams, "GRM": .grams,
        "KG": .kilograms, "KGS": .kilograms,
        "ML": .milliliters, "MLS": .milliliters,
        "L": .liters, "LT": .liters, "LTR": .liters
    ]

    /// Reads the quantity stated on a receipt line.
    ///
    /// Weight and volume win over a count: `2 @ CHKN 500G` describes two
    /// packs of 500 g, and 500 g is the more useful pantry number.
    func quantity(in text: String) -> ReceiptQuantity? {
        measurement(in: text) ?? count(in: text)
    }

    // MARK: - Weight and volume

    /// Finds the first `<number><unit>` pair, whether written `500G`,
    /// `500 G` or `1.25 kg`.
    private func measurement(in text: String) -> ReceiptQuantity? {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        for (index, token) in tokens.enumerated() {
            let split = Self.splitLeadingNumber(token)
            guard let value = split.value else { continue }

            // "500G" - the unit is stuck to the number.
            if !split.remainder.isEmpty, let unit = Self.unit(for: split.remainder) {
                return ReceiptQuantity(value: value, unit: unit)
            }

            // "500 G" - the unit is the next token. Only the unit itself may
            // follow, so "2 TOMATOES" isn't read as 2 tomato-units.
            if split.remainder.isEmpty,
               index + 1 < tokens.count,
               let unit = Self.unit(for: tokens[index + 1]) {
                return ReceiptQuantity(value: value, unit: unit)
            }
        }

        return nil
    }

    /// Resolves a unit suffix, rejecting anything that isn't exactly one.
    /// Trailing punctuation is tolerated because OCR leaves it behind.
    private static func unit(for token: String) -> MeasurementUnit? {
        let cleaned = token
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)]"))
            .uppercased()
        return unitsBySuffix[cleaned]
    }

    // MARK: - Counts

    /// Reads a `2 @ $3.00` or `3 x 1.50` multiplier as a count of units.
    ///
    /// Only this shape counts. A bare leading number is deliberately
    /// ignored: on receipts it is as often a line number or a PLU as a
    /// quantity, and a wrong count is worse than no count.
    private func count(in text: String) -> ReceiptQuantity? {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        for (index, token) in tokens.enumerated() {
            let split = Self.splitLeadingNumber(token)
            guard let value = split.value, value > 0, value <= 99 else { continue }

            // "2@" written together, or "2" followed by "@".
            let hasAttachedSeparator = Self.isMultiplier(split.remainder)
            let hasNextSeparator = split.remainder.isEmpty
                && index + 1 < tokens.count
                && Self.isMultiplier(tokens[index + 1])

            guard hasAttachedSeparator || hasNextSeparator else { continue }
            guard value.truncatingRemainder(dividingBy: 1) == 0 else { continue }

            return ReceiptQuantity(value: value, unit: .pieces)
        }

        return nil
    }

    private static func isMultiplier(_ token: String) -> Bool {
        let upper = token.uppercased()
        return upper == "@" || upper == "X" || upper.hasPrefix("@")
    }

    // MARK: - Scanning

    /// Splits a token into its leading decimal number and whatever follows.
    ///
    /// `"1.25KG"` becomes `(1.25, "KG")`, `"500"` becomes `(500, "")`, and
    /// `"CHKN"` becomes `(nil, "CHKN")`.
    static func splitLeadingNumber(_ token: String) -> (value: Double?, remainder: String) {
        var digits = ""
        var index = token.startIndex
        var hasSeparator = false

        while index < token.endIndex {
            let character = token[index]
            if character.isNumber {
                digits.append(character)
            } else if (character == "." || character == ",") && !hasSeparator && !digits.isEmpty {
                // Only a separator between digits counts, so a trailing
                // full stop doesn't become part of the number.
                let next = token.index(after: index)
                guard next < token.endIndex, token[next].isNumber else { break }
                hasSeparator = true
                digits.append(".")
            } else {
                break
            }
            index = token.index(after: index)
        }

        guard !digits.isEmpty, let value = Double(digits) else {
            return (nil, token)
        }
        return (value, String(token[index...]))
    }

    /// Whether `value` is written somewhere in `text`, used to sanity-check
    /// a quantity the model proposed against the receipt it came from.
    static func text(_ text: String, states: Double) -> Bool {
        let whole = states.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", states)
            : nil
        let candidates = [whole, String(states), String(format: "%g", states)].compactMap { $0 }

        let digitsOnly = text.replacingOccurrences(of: ",", with: ".")
        return candidates.contains { digitsOnly.contains($0) }
    }
}
