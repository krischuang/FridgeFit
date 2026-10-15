//
//  PackagedFoodTextReader.swift
//  FridgeFit
//

import CoreGraphics
import Foundation
import NaturalLanguage
import OSLog
import UIKit
import Vision

/// What OCR found on packaging, and what it might mean.
nonisolated struct PackagedFoodReading: Equatable, Sendable {
    /// Every line of text read, in Vision's order. Shown to the user so a
    /// suggestion can always be traced back to the words it came from, and
    /// so unmatched packaging is still useful information.
    let lines: [String]
    /// Ingredient candidates found in that text. **Always candidates** - see
    /// `PackagedFoodMatch.certainty`.
    let matches: [PackagedFoodMatch]
    /// Lines that are not predominantly Latin script, and so could never
    /// match an English vocabulary. Reported separately rather than counted
    /// as a matching failure.
    let nonLatinLines: [String]

    static let empty = PackagedFoodReading(lines: [], matches: [], nonLatinLines: [])

    var isEmpty: Bool { lines.isEmpty }
    /// True when there is no packaging in the photo at all - the common case
    /// for loose produce, and not an error.
    var foundNoText: Bool { lines.isEmpty }
}

/// How much weight an OCR match deserves.
///
/// There is no `verified` case, deliberately. Text on a package is evidence
/// about the *product*, not about the ingredient: a cereal box reading "RICE"
/// is not a bag of rice, and a freezer label reading "ICE CREAM" is not a
/// carton of cream. Only a user can close that gap.
nonisolated enum OCRMatchCertainty: String, Equatable, Sendable {
    /// The ingredient word is the clear subject of the text.
    case likely
    /// Found, but with something that weakens it - a qualifier, an ambiguous
    /// context, or a low-confidence line.
    case uncertain

    var displayName: String {
        switch self {
        case .likely: return "Likely"
        case .uncertain: return "Uncertain"
        }
    }
}

/// One ingredient term found in packaging text.
nonisolated struct PackagedFoodMatch: Identifiable, Equatable, Sendable {
    let id: UUID
    let ingredientId: String
    let displayName: String
    let category: IngredientGroup
    /// The line the match came from, verbatim.
    let sourceLine: String
    /// The exact text that matched, so a reviewer can see *why*.
    let matchedText: String
    /// Vision's confidence in having read that line correctly. **Not**
    /// confidence that the product is the ingredient.
    let textConfidence: Float
    let certainty: OCRMatchCertainty

    init(
        id: UUID = UUID(),
        ingredientId: String,
        displayName: String,
        category: IngredientGroup,
        sourceLine: String,
        matchedText: String,
        textConfidence: Float,
        certainty: OCRMatchCertainty
    ) {
        self.id = id
        self.ingredientId = ingredientId
        self.displayName = displayName
        self.category = category
        self.sourceLine = sourceLine
        self.matchedText = matchedText
        self.textConfidence = textConfidence
        self.certainty = certainty
    }
}

/// Reads packaging text from a captured photo and matches it against the
/// ingredient vocabulary.
///
/// ## Why this exists
///
/// Packaged goods are the one category image classification cannot do:
/// Apple Vision scored 0% on the pantry images at every threshold, returning
/// `container` and `cardboard_box` rather than the product. The text on the
/// box is the signal, and Vision reads it well - 29 lines from a packed
/// grocery shelf.
///
/// ## Why it is safe to run unconditionally
///
/// OCR self-gates. Across the evaluation set it produced **zero** lines on
/// all eight unpackaged-food images and text only on the three with
/// packaging. It cannot pollute results for loose produce, because there is
/// nothing for it to read.
///
/// ## Why automatic matching is off by default
///
/// Reading text is reliable; turning text into an ingredient is not. On the
/// evaluation set the first matcher produced exactly one match and it was
/// wrong (`ICE CREAM` → `cream_carton`). Matching is therefore opt-in
/// (`Configuration.automaticMatchingEnabled`, default `false`), and when it
/// is off the lines are still returned for the user to read. See
/// `docs/hybrid-stage2-results.md`.
///
/// ## Why it is not on the live path
///
/// Recognition took 20-500 ms per image in measurement, scaling with how
/// much text is present. That is far outside a 3 FPS live budget and would
/// stall frame handling. It runs on the captured still, off the main actor.
nonisolated final class PackagedFoodTextReader: Sendable {

    nonisolated struct Configuration: Sendable {
        /// Lines Vision is less sure of than this are ignored entirely.
        var minimumTextConfidence: Float = 0.30
        /// Lines below this are still matched, but only ever `.uncertain`.
        var confidentTextThreshold: Float = 0.60
        /// Whether to map text onto ingredients at all.
        ///
        /// Default **off**: matching has not been demonstrated reliable on
        /// any real packaging we have measured. With it off, `read` still
        /// returns every line, which is the part that does work.
        var automaticMatchingEnabled: Bool = false

        static let `default` = Configuration()
        /// For tests and for the evaluation harness.
        static var matching: Configuration {
            var configuration = Configuration()
            configuration.automaticMatchingEnabled = true
            return configuration
        }
    }

    private let taxonomy: IngredientTaxonomy
    private let configuration: Configuration
    private let logger = Logger(subsystem: "com.Fridge.FridgeFit", category: "PackagingOCR")

    init(taxonomy: IngredientTaxonomy, configuration: Configuration = .default) {
        self.taxonomy = taxonomy
        self.configuration = configuration
    }

    // MARK: - Reading

    /// Reads a captured photo.
    ///
    /// - Throws: only when the image cannot be read at all. Finding no text
    ///   is a normal result, not an error.
    func read(_ image: UIImage) throws -> PackagedFoodReading {
        guard let cgImage = image.cgImage else {
            throw VisionClassificationError.unreadableImage
        }
        return try read(cgImage, orientation: image.cgImagePropertyOrientation)
    }

    func read(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> PackagedFoodReading {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Packaging is multilingual far more often than a fridge is - the
        // evaluation set alone had Cyrillic and Greek. Letting Vision detect
        // the language beats pinning it to the device locale.
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw VisionClassificationError.requestFailed(reason: error.localizedDescription)
        }

        var lines: [(text: String, confidence: Float)] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= VNConfidence(configuration.minimumTextConfidence)
            else { continue }
            lines.append((candidate.string, Float(candidate.confidence)))
        }

        let nonLatin = lines.map(\.text).filter { !Self.isPredominantlyLatin($0) }

        return PackagedFoodReading(
            lines: lines.map(\.text),
            matches: configuration.automaticMatchingEnabled ? matches(in: lines) : [],
            nonLatinLines: nonLatin
        )
    }

    // MARK: - Script

    /// Whether a line is mostly Latin letters.
    ///
    /// An English vocabulary cannot match Cyrillic or Greek, so those lines
    /// are separated out rather than counted as matching failures. Without
    /// this the evaluation conflates "the matcher is bad" with "the matcher
    /// was given Russian".
    static func isPredominantlyLatin(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return true }  // digits only: nothing to mismatch
        let latin = letters.filter { $0.value < 0x0250 }
        return Double(latin.count) / Double(letters.count) >= 0.6
    }

    // MARK: - Matching

    /// Words that describe *packaging*, not the food inside it.
    ///
    /// The detection vocabulary is phrased for a camera - "bag of rice",
    /// "block of cheese", "milk carton" - because that is what an object
    /// detector sees. A label on a shelf says `RICE`. Matching the full
    /// vocabulary phrase against packaging text therefore finds nothing.
    static let packagingWords: Set<String> = [
        "bag", "of", "block", "sliced", "pot", "carton", "bottle", "loaf",
        "tin", "can", "jar", "box", "pack", "packet", "tub", "tray",
        "raw", "fresh", "whole", "piece", "pieces", "fillet", "steak",
    ]

    /// Compound products that contain an ingredient word but are a different
    /// food.
    ///
    /// This is the fix for the one match the evaluation produced, which was
    /// wrong: `ICE CREAM - ΠΑΓΩΤΑ` matched `cream_carton`, because "cream" is
    /// a legitimate whole word inside "ice cream". Whole-word matching is
    /// necessary but not sufficient - the surrounding words change what the
    /// word denotes.
    ///
    /// A match is rejected when it falls inside one of these phrases.
    static let misleadingCompounds: Set<String> = [
        "ice cream", "cream soda", "cream cracker", "cream egg",
        "sour cream", "cream of tartar", "creamed",
        "milk chocolate", "chocolate milk", "milkshake", "malted milk",
        "coconut milk", "milk of magnesia",
        "butter bean", "butter beans", "cocoa butter", "shea butter",
        "body butter", "buttermilk", "butterscotch", "butterfly",
        "peanut butter", "almond butter",
        "egg custard", "eggnog", "eggplant",
        "cheesecake", "cheese flavour", "cheese flavoured", "cheesy",
        "rice pudding", "rice cake", "rice cakes", "rice paper",
        "bread crumbs", "breadcrumbs", "shortbread", "gingerbread",
        "sugar free", "sugar-free", "no added sugar",
        "fish oil", "fish food", "cuttlefish", "shellfish allergy",
        "chicken flavour", "chicken flavoured", "chicken stock",
        "beef flavour", "beef stock", "beef tomato",
        "corned beef",
    ]

    /// Qualifiers that make a match weaker rather than wrong.
    ///
    /// "Strawberry flavour yoghurt" does contain yoghurt, but a line that is
    /// mostly marketing is weaker evidence than a line reading "YOGHURT".
    static let weakeningQualifiers: Set<String> = [
        "flavour", "flavor", "flavoured", "flavored", "style", "substitute",
        "alternative", "free", "like", "imitation", "artificial", "essence",
    ]

    /// The searchable part of a vocabulary term.
    ///
    /// `"bag of rice"` → `"rice"`, `"jar of peanut butter"` → `"peanut
    /// butter"`, `"tin can"` → `nil` (nothing but packaging left, so there is
    /// no food word to look for).
    static func searchKey(for term: String) -> String? {
        let words = term.lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { !packagingWords.contains($0) }
        guard !words.isEmpty else { return nil }
        let key = words.joined(separator: " ")
        // Two-letter remnants are noise in OCR text.
        return key.count >= 3 ? key : nil
    }

    /// Finds ingredient candidates in OCR lines.
    ///
    /// Deliberately deterministic string matching. Apple's Foundation Models
    /// could structure this better, but it is unavailable on ineligible
    /// devices and this path has to work everywhere; a deterministic matcher
    /// is also something the tests can pin exactly.
    ///
    /// English only. Non-Latin lines are skipped here and reported through
    /// `PackagedFoodReading.nonLatinLines`.
    func matches(in lines: [(text: String, confidence: Float)]) -> [PackagedFoodMatch] {
        var found: [PackagedFoodMatch] = []
        var seen = Set<String>()

        // Built once per call, ordered longest key first so the most specific
        // term wins: "PEANUT BUTTER" must match `jar of peanut butter`, not
        // `butter`.
        let searchable: [(key: String, definition: IngredientDefinition)] =
            taxonomy.definitions
                .filter(\.category.isIngredient)
                .compactMap { definition in
                    Self.searchKey(for: definition.term).map { ($0, definition) }
                }
                .sorted { $0.0.count > $1.0.count }

        for line in lines {
            guard Self.isPredominantlyLatin(line.text) else { continue }

            let haystack = line.text.lowercased()
            // Spans occupied by a misleading compound. A match landing inside
            // one of these is about a different food.
            let blocked = Self.blockedRanges(in: haystack)
            // Consumed as matches are found, so a longer key that has already
            // claimed some text stops a shorter one re-matching inside it.
            var remaining = haystack

            for (key, definition) in searchable {
                guard !seen.contains(definition.ingredient) else { continue }

                let range: Range<String.Index>?
                if key.contains(" ") {
                    // A compound key - "peanut butter" - is matched as a
                    // phrase, since its words are meaningless apart.
                    range = remaining.range(of: key)
                } else {
                    // Single words must match whole, or "ham" finds "hammer"
                    // and "rice" finds "price".
                    range = Self.wholeWordRange(of: key, in: remaining)
                }
                guard let range else { continue }

                // The core fix: reject when the hit sits *inside* a longer
                // compound that means something else.
                //
                // "Strictly inside" is the operative word. `peanut butter` is
                // both a legitimate ingredient key and a phrase that must
                // block a bare `butter`; blocking any overlap would make it
                // block itself. So a compound only disqualifies a match that
                // it properly contains.
                if blocked.contains(where: { $0.lowerBound <= range.lowerBound
                                            && $0.upperBound >= range.upperBound
                                            && $0 != range }) {
                    continue
                }

                remaining.replaceSubrange(range, with: String(repeating: " ", count: key.count))
                seen.insert(definition.ingredient)

                let weakened = Self.containsWeakeningQualifier(haystack)
                let certainty: OCRMatchCertainty =
                    (weakened || line.confidence < configuration.confidentTextThreshold)
                        ? .uncertain : .likely

                found.append(PackagedFoodMatch(
                    ingredientId: definition.ingredient,
                    displayName: definition.display,
                    category: definition.category,
                    sourceLine: line.text,
                    matchedText: String(haystack[range]),
                    textConfidence: line.confidence,
                    certainty: certainty
                ))
            }
        }
        return found
    }

    /// Ranges in `haystack` covered by a misleading compound phrase.
    static func blockedRanges(in haystack: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        for compound in misleadingCompounds {
            var searchStart = haystack.startIndex
            while let range = haystack.range(of: compound, range: searchStart..<haystack.endIndex) {
                ranges.append(range)
                guard range.upperBound < haystack.endIndex else { break }
                searchStart = range.upperBound
            }
        }
        return ranges
    }

    static func containsWeakeningQualifier(_ haystack: String) -> Bool {
        let words = Set(haystack.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return !words.isDisjoint(with: weakeningQualifiers)
    }

    /// Range of `word` in `text`, only where it stands as a whole word.
    static func wholeWordRange(of word: String, in text: String) -> Range<String.Index>? {
        var searchStart = text.startIndex
        while let range = text.range(of: word, range: searchStart..<text.endIndex) {
            let beforeOK = range.lowerBound == text.startIndex
                || !isWordCharacter(text[text.index(before: range.lowerBound)])
            let afterOK = range.upperBound == text.endIndex
                || !isWordCharacter(text[range.upperBound])
            if beforeOK && afterOK { return range }
            guard range.upperBound < text.endIndex else { return nil }
            searchStart = range.upperBound
        }
        return nil
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
