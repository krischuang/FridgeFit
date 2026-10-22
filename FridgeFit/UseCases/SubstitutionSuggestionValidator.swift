//
//  SubstitutionSuggestionValidator.swift
//  FridgeFit
//

import Foundation

/// Turns an untrusted `RawSubstitutionSuggestion` into a `SubstitutionSuggestion`
/// by checking it against the real pantry - the one place allowed to decide
/// pantry existence, quantity sufficiency, and unit compatibility.
///
/// The LLM is never trusted for any of that. This type doesn't call the
/// provider or know about caching; `GetIngredientSubstitutionsUseCase`
/// handles that.
nonisolated enum SubstitutionSuggestionValidator {
    /// Validates one candidate.
    ///
    /// - Returns: `nil` if the candidate is structurally invalid (blank
    ///   name or explanation) and should be dropped entirely - that's not
    ///   a "rejected" suggestion, it's not a suggestion at all.
    static func validate(
        _ raw: RawSubstitutionSuggestion,
        against pantryItems: [PantryItem],
        dietaryRestrictions: [String]
    ) -> SubstitutionSuggestion? {
        let trimmedName = raw.ingredientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExplanation = raw.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedExplanation.isEmpty else {
            return nil
        }

        let suggestedUnit = raw.suggestedUnit
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { MeasurementUnit(rawValue: $0) }
        let confidence = raw.confidence.map { min(max($0, 0), 1) }
        let limitations = raw.limitations?.trimmingCharacters(in: .whitespacesAndNewlines)

        if conflictsWithRestriction(ingredientName: trimmedName, restrictions: dietaryRestrictions) {
            return SubstitutionSuggestion(
                ingredientName: trimmedName,
                suggestedQuantity: raw.suggestedQuantity,
                suggestedUnit: suggestedUnit,
                confidence: confidence,
                explanation: trimmedExplanation,
                limitations: limitations,
                pantryQuantity: nil,
                pantryUnit: nil,
                validationStatus: .rejected
            )
        }

        guard let pantryItem = pantryItems.first(where: {
            IngredientNameMatching.covers(pantryName: $0.ingredient.name, recipeName: trimmedName)
        }) else {
            return SubstitutionSuggestion(
                ingredientName: trimmedName,
                suggestedQuantity: raw.suggestedQuantity,
                suggestedUnit: suggestedUnit,
                confidence: confidence,
                explanation: trimmedExplanation,
                limitations: limitations,
                pantryQuantity: nil,
                pantryUnit: nil,
                validationStatus: .notInPantry
            )
        }

        // In the pantry. Without a specific suggested quantity/unit from
        // the provider, all we can confirm is presence.
        guard let suggestedQuantity = raw.suggestedQuantity, let suggestedUnit else {
            return SubstitutionSuggestion(
                ingredientName: trimmedName,
                suggestedQuantity: raw.suggestedQuantity,
                suggestedUnit: suggestedUnit,
                confidence: confidence,
                explanation: trimmedExplanation,
                limitations: limitations,
                pantryQuantity: pantryItem.quantity,
                pantryUnit: pantryItem.unit,
                validationStatus: .availableInPantry
            )
        }

        guard let convertedPantryQuantity = MeasurementUnit.convert(quantity: pantryItem.quantity, from: pantryItem.unit, to: suggestedUnit) else {
            return SubstitutionSuggestion(
                ingredientName: trimmedName,
                suggestedQuantity: suggestedQuantity,
                suggestedUnit: suggestedUnit,
                confidence: confidence,
                explanation: trimmedExplanation,
                limitations: limitations,
                pantryQuantity: pantryItem.quantity,
                pantryUnit: pantryItem.unit,
                validationStatus: .unsupportedUnit
            )
        }

        let status: SubstitutionValidationStatus = convertedPantryQuantity >= suggestedQuantity ? .availableInPantry : .insufficientQuantity
        return SubstitutionSuggestion(
            ingredientName: trimmedName,
            suggestedQuantity: suggestedQuantity,
            suggestedUnit: suggestedUnit,
            confidence: confidence,
            explanation: trimmedExplanation,
            limitations: limitations,
            pantryQuantity: pantryItem.quantity,
            pantryUnit: pantryItem.unit,
            validationStatus: status
        )
    }

    /// A deliberately simple, deterministic keyword check - not a medical
    /// allergen database. `dietaryRestrictions` is always empty until a
    /// future phase adds a real profile, so this is inert today but ready
    /// for when it isn't.
    private static func conflictsWithRestriction(ingredientName: String, restrictions: [String]) -> Bool {
        restrictions.contains { restriction in
            let trimmed = restriction.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && ingredientName.localizedCaseInsensitiveContains(trimmed)
        }
    }
}
