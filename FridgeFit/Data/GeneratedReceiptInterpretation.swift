//
//  GeneratedReceiptInterpretation.swift
//  FridgeFit
//

import FoundationModels

/// The guided-generation schema the on-device model fills in for a batch of
/// receipt lines.
///
/// Provider-specific on purpose - these types exist to constrain
/// `FoundationModels` output and nothing else, which is why they live in
/// the data layer and get mapped straight onto `RawInterpretedReceiptItem`
/// rather than being passed around the app.
///
/// Three deliberate schema choices:
///
/// - **No `Optional` properties.** Guided generation is happier producing a
///   sentinel than an absent field, so "the receipt didn't say how much" is
///   `quantity == 0` with `unit == .notStated`, not `nil`.
/// - **Enums, not free strings,** for classification, category and unit, so
///   the model can only pick a value FridgeFit already understands.
/// - **`originalText` is echoed back.** It is how an interpretation is
///   matched to the line it came from, and it is the check that stops an
///   invented grocery from reaching the pantry: `ReceiptItemNormalizer`
///   drops any item whose echo doesn't correspond to a line that was
///   actually sent.
@Generable(description: "Interpretation of product lines read from a grocery receipt")
struct GeneratedReceiptInterpretation {
    @Guide(
        description: "One entry for each receipt line you were given, in the same order. Never add an entry for a product that was not in the input.",
        .maximumCount(40)
    )
    var items: [GeneratedReceiptItem]
}

@Generable(description: "One product line from a grocery receipt, interpreted")
struct GeneratedReceiptItem {
    @Guide(description: "The receipt line you are interpreting, copied exactly as it was given to you, with no changes.")
    var originalText: String

    @Guide(description: "The product written in plain English, such as 'Chicken Breast' or 'Red Capsicum'. Expand abbreviations. No brand names, no pack sizes, no prices.")
    var displayName: String

    @Guide(description: "The base ingredient in lowercase singular form, with no colour, size, cut or brand. For example 'chicken' for a chicken breast, 'capsicum' for a red capsicum, 'mushroom' for cup mushrooms.")
    var canonicalName: String

    @Guide(description: "What kind of purchase this line is")
    var classification: GeneratedReceiptItemClassification

    @Guide(description: "Which food group this belongs to. Use 'other' for anything that is not food.")
    var category: GeneratedIngredientCategory

    @Guide(
        description: "The amount printed on this receipt line, such as 500 for '500G'. Use 0 when the line does not state an amount. Never estimate.",
        .range(0 ... 100_000)
    )
    var quantity: Double

    @Guide(description: "The unit of the amount printed on this line. Use 'notStated' when the line does not state one.")
    var unit: GeneratedReceiptUnit
}

/// Mirrors `ReceiptItemClassification`.
@Generable
enum GeneratedReceiptItemClassification {
    /// Food a recipe could call for.
    case ingredient
    /// Edible, but not something you cook with.
    case foodNonIngredient
    /// A drink.
    case beverage
    /// Cleaning, kitchen or pet supplies.
    case household
    /// Toiletries, cosmetics or medicine.
    case personalCare
    /// The line could not be read confidently enough to say.
    case unknown
}

/// Mirrors `IngredientCategory`. Kept separate so the shared domain model
/// doesn't have to import `FoundationModels`.
@Generable
enum GeneratedIngredientCategory {
    case produce
    case dairy
    case meat
    case grain
    case spiceOrCondiment
    case other
}

/// Mirrors the subset of `MeasurementUnit` that appears on receipts, plus
/// an explicit "the receipt didn't say" case.
@Generable
enum GeneratedReceiptUnit {
    case notStated
    case grams
    case kilograms
    case milliliters
    case liters
    case pieces
}

extension GeneratedReceiptInterpretation {
    /// Flattens the generated interpretation into untrusted raw items.
    ///
    /// Only translation happens here - no filtering, matching or
    /// canonicalization. That's `ReceiptItemNormalizer`'s job, so those
    /// rules live in one place regardless of which provider produced the
    /// interpretation.
    var rawItems: [RawInterpretedReceiptItem] {
        items.map { item in
            RawInterpretedReceiptItem(
                originalText: item.originalText,
                displayName: item.displayName,
                canonicalName: item.canonicalName,
                classification: item.classification.classification.rawValue,
                category: item.category.ingredientCategory.rawValue,
                quantity: item.quantity,
                unit: item.unit.measurementUnit?.rawValue ?? ""
            )
        }
    }
}

extension GeneratedReceiptItemClassification {
    var classification: ReceiptItemClassification {
        switch self {
        case .ingredient: return .ingredient
        case .foodNonIngredient: return .foodNonIngredient
        case .beverage: return .beverage
        case .household: return .household
        case .personalCare: return .personalCare
        case .unknown: return .unknown
        }
    }
}

extension GeneratedIngredientCategory {
    var ingredientCategory: IngredientCategory {
        switch self {
        case .produce: return .produce
        case .dairy: return .dairy
        case .meat: return .meat
        case .grain: return .grain
        case .spiceOrCondiment: return .spice
        case .other: return .other
        }
    }
}

extension GeneratedReceiptUnit {
    /// `nil` for `notStated`, which is the whole point of that case.
    var measurementUnit: MeasurementUnit? {
        switch self {
        case .notStated: return nil
        case .grams: return .grams
        case .kilograms: return .kilograms
        case .milliliters: return .milliliters
        case .liters: return .liters
        case .pieces: return .pieces
        }
    }
}
