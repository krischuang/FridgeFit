//
//  GeneratedSubstitutionSuggestions.swift
//  FridgeFit
//

import Foundation
import FoundationModels

/// The guided-generation schema the on-device model fills in when asked for
/// substitutes for one recipe ingredient.
///
/// Provider-specific on purpose, exactly like `GeneratedReceiptInterpretation`:
/// these types exist to constrain `FoundationModels` output and nothing else,
/// which is why they live in the data layer and are mapped straight onto
/// `RawSubstitutionSuggestion` rather than being passed around the app.
///
/// Note what the model is *not* asked for. There is no "in the pantry" flag,
/// no on-hand quantity and no allergen-safety field. Those are decided by
/// `SubstitutionSuggestionValidator` against the real pantry - asking the
/// model for them would be inviting it to contradict FridgeFit's own data.
///
/// Three deliberate schema choices, inherited from the receipt scanner:
///
/// - **No `Optional` properties.** Guided generation produces a sentinel far
///   more reliably than an absent field, so "no specific amount" is
///   `suggestedQuantity == 0` with `suggestedUnit == .notStated`, and "no
///   limitations worth mentioning" is an empty `limitations` string.
/// - **Enums, not free strings,** for the unit, so the model can only pick a
///   symbol `MeasurementUnit` already understands.
/// - **A small integer scale for suitability** rather than a 0-1 float. A
///   on-device model picks reliably from five labelled steps; asking it for
///   "0.73" invites a number with no meaning behind it.
@Generable(description: "Culinary substitutes for one ingredient a recipe calls for")
struct GeneratedSubstitutionSuggestions {
    @Guide(
        description: "Substitutes for the ingredient you were asked about, best first. Return only substitutes you are confident about - two good ones beat three with a filler.",
        .maximumCount(3)
    )
    var suggestions: [GeneratedSubstitutionSuggestion]
}

@Generable(description: "One substitute for the ingredient a recipe calls for")
struct GeneratedSubstitutionSuggestion {
    @Guide(description: "The substitute's everyday name, such as 'Greek yogurt' or 'olive oil'. No brand names, no pack sizes, no quantities in the name.")
    var ingredientName: String

    @Guide(
        description: "How much of the substitute to use in place of the required amount, such as 200 for 200 ml. Use 0 when the swap is not a simple measured amount.",
        .range(0 ... 100_000)
    )
    var suggestedQuantity: Double

    @Guide(description: "The unit for suggestedQuantity. Use 'notStated' whenever suggestedQuantity is 0.")
    var suggestedUnit: GeneratedSubstitutionUnit

    @Guide(
        description: "How well this substitute works in this particular recipe: 5 is nearly indistinguishable, 3 works with a noticeable difference, 1 is a last resort.",
        .range(1 ... 5)
    )
    var suitability: Int

    @Guide(description: "One or two short sentences on why this works in this recipe, written for a home cook.")
    var explanation: String

    @Guide(description: "How the dish will differ in texture, flavour or cooking behaviour. Use an empty string only when there is genuinely no difference worth mentioning.")
    var limitations: String
}

/// Mirrors `MeasurementUnit`, plus an explicit "no specific amount" case.
///
/// Kept separate so the shared domain model doesn't have to import
/// `FoundationModels` - the same split `GeneratedReceiptUnit` uses.
@Generable
enum GeneratedSubstitutionUnit {
    /// The swap isn't a simple measured amount.
    case notStated
    case grams
    case kilograms
    case milliliters
    case liters
    case pieces
    case cups
    case tablespoons
    case teaspoons
}

extension GeneratedSubstitutionSuggestions {
    /// Translates generated output into untrusted raw suggestions.
    ///
    /// Only translation happens here - no filtering, deduplication, pantry
    /// matching or dietary checks. Those stay in
    /// `SubstitutionSuggestionValidator` and
    /// `GetIngredientSubstitutionsUseCase` so the rules live in one place
    /// regardless of which provider produced the suggestion.
    var rawSuggestions: [RawSubstitutionSuggestion] {
        suggestions.map(\.rawSuggestion)
    }
}

extension GeneratedSubstitutionSuggestion {
    var rawSuggestion: RawSubstitutionSuggestion {
        // A quantity without a unit can't be validated against the pantry,
        // and a unit with no quantity says nothing, so the two travel
        // together or not at all. Either half missing drops both, which is
        // exactly the state `SubstitutionSuggestionValidator` reads as
        // "all we can confirm is presence".
        let unit = suggestedUnit.measurementUnit
        let hasUsableAmount = unit != nil && suggestedQuantity > 0

        let trimmedLimitations = limitations.trimmingCharacters(in: .whitespacesAndNewlines)

        return RawSubstitutionSuggestion(
            ingredientName: ingredientName,
            suggestedQuantity: hasUsableAmount ? suggestedQuantity : nil,
            suggestedUnit: hasUsableAmount ? unit?.rawValue : nil,
            confidence: Self.confidence(forSuitability: suitability),
            explanation: explanation,
            limitations: trimmedLimitations.isEmpty ? nil : trimmedLimitations
        )
    }

    /// Maps the 1-5 suitability scale onto the 0-1 `confidence` the rest of
    /// the app already carries, so the field keeps its existing contract.
    ///
    /// Clamped because a guided range is a strong hint, not a guarantee.
    /// Deliberately never reaches 0: a suggestion the model returned at all
    /// is not zero-confidence, and `confidence` is informational only - it
    /// never decides pantry availability or ordering.
    static func confidence(forSuitability suitability: Int) -> Double {
        let clamped = min(max(suitability, 1), 5)
        return Double(clamped) / 5.0
    }
}

extension GeneratedSubstitutionUnit {
    /// `nil` for `notStated`, which is the whole point of that case.
    var measurementUnit: MeasurementUnit? {
        switch self {
        case .notStated: return nil
        case .grams: return .grams
        case .kilograms: return .kilograms
        case .milliliters: return .milliliters
        case .liters: return .liters
        case .pieces: return .pieces
        case .cups: return .cups
        case .tablespoons: return .tablespoons
        case .teaspoons: return .teaspoons
        }
    }
}
