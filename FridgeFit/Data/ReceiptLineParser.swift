//
//  ReceiptLineParser.swift
//  FridgeFit
//

import Foundation

/// Turns raw OCR lines into candidate product lines.
///
/// ## Deliberately a weak filter
///
/// This layer only removes what is *unambiguously* not a purchased
/// product - totals, payment lines, dates, blank noise. Anything it is not
/// sure about is kept and passed to `ReceiptIngredientInterpreter`, which
/// has actual language understanding and will classify a store name as
/// `unknown` and a cleaning product as `household` perfectly well.
///
/// That asymmetry is intentional. A line wrongly dropped here is invisible:
/// the user never learns their chicken didn't make it. A line wrongly kept
/// costs one extra entry in a list the model is about to triage anyway. So
/// when in doubt, keep.
///
/// It is also why there is no retailer-specific parsing. Chasing the layout
/// of every Australian supermarket would be a large, brittle, permanently
/// incomplete body of pattern matching; the model is better at reading
/// `CHKN BREAST 500G` than any rule we could write.
///
/// `originalText` is never modified - only `productDescription` is cleaned,
/// so the interpreter and the UI can both still see exactly what was
/// printed.
nonisolated struct ReceiptLineParser {
    /// Hard cap on lines considered, so a photo of a wall of text can't
    /// turn into an enormous model prompt.
    private static let maximumLineCount = 200
    /// Shorter than this and there is no product name left to interpret.
    private static let minimumDescriptionLength = 2

    /// Words that are never part of a product name on a grocery receipt.
    /// Matched as whole words, so `CASHEWS` survives `CASH` and
    /// `CARDAMOM` survives `CARD`.
    private static let metadataWords: Set<String> = [
        "SUBTOTAL", "SUBTOT", "TOTALS", "GST", "ABN", "ACN", "EFTPOS", "EFT",
        "VISA", "MASTERCARD", "AMEX", "DEBIT", "CREDIT", "CASH", "CHANGE",
        "ROUNDING", "ROUNDED", "TENDERED", "AUTH", "APPROVED", "DECLINED",
        "TERMINAL", "MERCHANT", "SIGNATURE", "RECEIPT", "INVOICE", "CASHIER",
        "OPERATOR", "REGISTER", "LOYALTY", "REWARDS", "POINTS", "EARNED",
        "SAVINGS", "SAVED", "TAX", "PURCHASE", "REFUND", "SURCHARGE",
        "PHONE", "TEL", "WWW", "HTTP", "HTTPS", "THANKYOU", "RETAIN"
    ]

    /// Multi-word phrases that mean metadata, checked as consecutive words.
    private static let metadataPhrases: [[String]] = [
        ["THANK", "YOU"],
        ["TAX", "INVOICE"],
        ["CUSTOMER", "COPY"],
        ["MERCHANT", "COPY"],
        ["PLEASE", "RETAIN"],
        ["SERVED", "BY"],
        ["ITEM", "COUNT"],
        ["NO", "OF", "ITEMS"]
    ]

    /// Words that start a metadata line but could legitimately begin a
    /// product name - `TOTAL` is a yoghurt brand, `ITEMS` could be
    /// anything. Treated as metadata only when nothing alphabetic follows,
    /// so `TOTAL 45.67` goes and `TOTAL GREEK YOGURT 6.00` stays.
    private static let ambiguousLeadingWords: Set<String> = [
        "TOTAL", "ITEMS", "ITEM", "BALANCE", "AMOUNT", "QTY", "COUNT", "DATE", "TIME", "STORE"
    ]

    func parse(_ recognized: RecognizedReceiptText) -> [ReceiptLineItem] {
        var items: [ReceiptLineItem] = []

        for line in recognized.lines.prefix(Self.maximumLineCount) {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            // A bare "2 @ $3.00" is quantity information for the product
            // above it, so fold it in rather than losing it.
            if Self.isMultiplierContinuation(text) {
                if let previous = items.popLast() {
                    items.append(
                        ReceiptLineItem(
                            originalText: "\(previous.originalText) \(text)",
                            productDescription: previous.productDescription,
                            price: previous.price,
                            order: previous.order
                        )
                    )
                }
                continue
            }

            guard !Self.isMetadata(text), Self.containsLetters(text) else { continue }

            let split = Self.splittingPrice(from: text)
            let cleaned = Self.cleaned(split.description)
            guard cleaned.count >= Self.minimumDescriptionLength, Self.containsLetters(cleaned) else { continue }

            items.append(
                ReceiptLineItem(
                    originalText: text,
                    productDescription: cleaned,
                    price: split.price,
                    order: line.order
                )
            )
        }

        return items
    }

    // MARK: - Classifying a line

    /// Whether a line is receipt furniture rather than a purchased product.
    static func isMetadata(_ text: String) -> Bool {
        let words = self.words(in: text)
        guard !words.isEmpty else { return true }

        if words.contains(where: metadataWords.contains) { return true }
        if metadataPhrases.contains(where: { contains($0, in: words) }) { return true }

        if let first = words.first, ambiguousLeadingWords.contains(first) {
            // Metadata only if the rest of the line is numbers and symbols.
            return words.dropFirst().allSatisfy { !$0.contains(where: \.isLetter) }
        }

        return false
    }

    /// A line like `2 @ $3.00` or `3 x 1.50`: a quantity and a price, with
    /// no product of its own.
    static func isMultiplierContinuation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        var index = trimmed.startIndex

        var digits = 0
        while index < trimmed.endIndex, trimmed[index].isNumber {
            digits += 1
            index = trimmed.index(after: index)
        }
        guard digits > 0, digits <= 3 else { return false }

        while index < trimmed.endIndex, trimmed[index] == " " {
            index = trimmed.index(after: index)
        }
        guard index < trimmed.endIndex else { return false }

        let separator = trimmed[index]
        guard separator == "@" || separator == "x" || separator == "X" else { return false }

        // Everything after the separator must be price-like, not a product
        // name - otherwise "2 x TOMATO" is a real product line.
        let remainder = trimmed[trimmed.index(after: index)...]
        return !remainder.contains { $0.isLetter }
    }

    /// Uppercased alphanumeric words, which is what word matching needs.
    private static func words(in text: String) -> [String] {
        text.uppercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func contains(_ phrase: [String], in words: [String]) -> Bool {
        guard phrase.count <= words.count else { return false }
        return (0 ... (words.count - phrase.count)).contains { start in
            Array(words[start ..< start + phrase.count]) == phrase
        }
    }

    private static func containsLetters(_ text: some StringProtocol) -> Bool {
        text.contains { $0.isLetter }
    }

    // MARK: - Cleaning

    /// Splits a trailing price off a line, keeping the rest as the
    /// description. Returns a `nil` price when the line doesn't end in one.
    ///
    /// Works on whitespace-separated tokens rather than a pattern over the
    /// whole string, because the only thing that reliably marks a receipt
    /// price is that it is the last thing on the line.
    static func splittingPrice(from text: String) -> (description: String, price: Double?) {
        var tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !tokens.isEmpty else { return (text, nil) }

        if let price = priceValue(of: tokens[tokens.count - 1]) {
            tokens.removeLast()
            return (tokens.joined(separator: " "), price)
        }

        // Some receipts print the tax flag as its own token: "8.50 T".
        if tokens.count >= 2,
           isTaxFlag(tokens[tokens.count - 1]),
           let price = priceValue(of: tokens[tokens.count - 2]) {
            tokens.removeLast(2)
            return (tokens.joined(separator: " "), price)
        }

        return (text, nil)
    }

    /// Reads a token as a money amount, tolerating a currency symbol and a
    /// trailing tax flag. Requires exactly two decimal places, which is
    /// what keeps `500G` and `2L` from being mistaken for prices.
    static func priceValue(of token: String) -> Double? {
        var body = Substring(token)

        if body.first == "$" { body = body.dropFirst() }
        while let last = body.last, last.isLetter || last == "*" || last == "#" {
            body = body.dropLast()
        }
        guard !body.isEmpty else { return nil }

        let separatorIndex = body.lastIndex(where: { $0 == "." || $0 == "," })
        guard let separatorIndex else { return nil }

        let whole = body[body.startIndex ..< separatorIndex]
        let fraction = body[body.index(after: separatorIndex)...]
        guard fraction.count == 2, fraction.allSatisfy(\.isNumber) else { return nil }
        guard !whole.isEmpty, whole.allSatisfy(\.isNumber) else { return nil }

        return Double("\(whole).\(fraction)")
    }

    private static func isTaxFlag(_ token: String) -> Bool {
        token.count <= 2 && token.allSatisfy { $0.isLetter || $0 == "*" || $0 == "#" }
    }

    /// Removes a leading barcode or PLU code and tidies separators, without
    /// touching the words themselves - abbreviations are the interpreter's
    /// problem, and "correcting" them here would throw away evidence.
    private static func cleaned(_ description: String) -> String {
        var tokens = description
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        if let first = tokens.first, first.count >= 5, first.allSatisfy(\.isNumber) {
            tokens.removeFirst()
        }

        return tokens
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t-–—*#.,:;|"))
    }
}
