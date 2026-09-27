//
//  DetectedIngredientNormalizer.swift
//  FridgeFit
//

import Foundation

/// Turns untrusted `RawDetectedIngredient`s into `DetectedIngredient`s,
/// deterministically.
///
/// The same role `SubstitutionSuggestionValidator` plays for substitutions:
/// everything a generative model says passes through here before any other
/// part of FridgeFit sees it, so the rules live in one testable place
/// instead of being spread across providers.
///
/// Rules applied, in order:
///
/// - Drop detections with a blank or implausibly long name.
/// - Drop names that are obviously not ingredients (containers, shelves,
///   and other things a fridge photo is full of), as a backstop to the
///   prompt.
/// - Normalize the name's whitespace and capitalisation to match how
///   `Ingredient` names are written elsewhere.
/// - Map the category string onto `IngredientCategory`, falling back to
///   `.other` for anything unrecognised.
/// - Map the confidence string onto `ModelStatedConfidence`, falling back to
///   `.low` - an unreadable confidence is not a confident detection.
/// - Clamp counts to a sane range, treating `0` as "couldn't tell".
/// - Collapse duplicates by normalized name, keeping the most confident.
struct DetectedIngredientNormalizer {
    /// Longer than any real ingredient name - anything past this is a
    /// sentence, not an ingredient.
    private static let maximumNameLength = 40

    /// Words that mean packaging or furniture rather than food. The prompt
    /// already asks the model to skip these; this catches the cases where
    /// it doesn't.
    private static let nonFoodTerms: Set<String> = [
        "shelf", "shelves", "fridge", "refrigerator", "freezer", "drawer",
        "container", "containers", "tupperware", "plate", "plates", "bowl",
        "bowls", "cup", "cups", "glass", "mug", "jar", "jars", "bottle",
        "bottles", "carton", "cartons", "can", "cans", "tin", "package",
        "packaging", "packet", "bag", "bags", "box", "boxes", "wrapper",
        "lid", "tray", "food", "ingredient", "ingredients", "leftovers",
        "kitchen", "door", "light", "shelving", "rack", "unknown", "none",
        // Material and state words, so "plastic container" and "empty jar"
        // are dropped as a whole rather than kept because one word isn't
        // packaging.
        "plastic", "paper", "metal", "cardboard", "empty", "opaque", "sealed",
        "wrapped", "clear", "assorted", "various", "item", "items", "object"
    ]

    func normalize(_ result: IngredientDetectionResult) -> [DetectedIngredient] {
        let detections = result.ingredients.compactMap(normalize(_:))
        return collapsingDuplicates(in: detections)
    }

    private func normalize(_ raw: RawDetectedIngredient) -> DetectedIngredient? {
        let collapsedName = raw.name
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !collapsedName.isEmpty, collapsedName.count <= Self.maximumNameLength else { return nil }
        guard !Self.isNonFood(collapsedName) else { return nil }

        return DetectedIngredient(
            name: Self.displayName(for: collapsedName),
            category: IngredientCategory(rawValue: raw.category) ?? .other,
            visibleCount: Self.clampedCount(raw.visibleCount),
            confidence: ModelStatedConfidence(rawValue: raw.confidence.lowercased()) ?? .low
        )
    }

    /// A name is non-food only if *every* word in it is a non-food term, so
    /// "milk carton" still normalizes to a detection while "carton" alone
    /// doesn't.
    private static func isNonFood(_ name: String) -> Bool {
        let words = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return true }
        return words.allSatisfy { nonFoodTerms.contains($0) }
    }

    /// Capitalises each word, matching how pantry items added by hand tend
    /// to read ("Greek Yogurt"), while leaving existing capitalisation in
    /// mixed-case names alone.
    private static func displayName(for name: String) -> String {
        name.components(separatedBy: " ")
            .map { word in
                guard let first = word.first else { return word }
                return word.allSatisfy { $0.isLowercase || !$0.isLetter }
                    ? first.uppercased() + word.dropFirst()
                    : word
            }
            .joined(separator: " ")
    }

    /// `0` means the model couldn't count, which is not the same as "zero
    /// of them". Negative or absurd counts are treated the same way.
    private static func clampedCount(_ count: Int) -> Int? {
        guard count > 0 else { return nil }
        return min(count, 50)
    }

    /// Keeps one detection per ingredient name, preferring the most
    /// confident and then the one with a usable count. Uses the same
    /// case-insensitive matching rule as the pantry.
    private func collapsingDuplicates(in detections: [DetectedIngredient]) -> [DetectedIngredient] {
        var bestByName: [String: DetectedIngredient] = [:]
        var order: [String] = []

        for detection in detections {
            let key = detection.name.lowercased()
            guard let existing = bestByName[key] else {
                bestByName[key] = detection
                order.append(key)
                continue
            }
            if Self.isBetter(detection, than: existing) {
                bestByName[key] = detection
            }
        }

        return order.compactMap { bestByName[$0] }
    }

    private static func isBetter(_ candidate: DetectedIngredient, than existing: DetectedIngredient) -> Bool {
        if candidate.confidence.sortPriority != existing.confidence.sortPriority {
            return candidate.confidence.sortPriority < existing.confidence.sortPriority
        }
        return candidate.visibleCount != nil && existing.visibleCount == nil
    }
}
