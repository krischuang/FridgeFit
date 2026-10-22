//
//  SubstitutionSuggestion.swift
//  FridgeFit
//

import Foundation

/// A substitution candidate after deterministic validation - what the UI
/// is allowed to show.
///
/// `pantryQuantity`/`pantryUnit`/`validationStatus` come entirely from
/// `SubstitutionSuggestionValidator` checking the real pantry, never from
/// the LLM - see `RawSubstitutionSuggestion`.
/// `Codable` so `SubstitutionCacheStore` can keep validated suggestions
/// across launches. Only ever encoded into that on-device cache - the
/// validated fields are re-derived from the real pantry whenever a
/// suggestion is generated, never read back from a wire format.
nonisolated struct SubstitutionSuggestion: Identifiable, Equatable, Codable {
    let id: UUID
    let ingredientName: String
    let suggestedQuantity: Double?
    let suggestedUnit: MeasurementUnit?
    /// The provider's own confidence, 0-1, clamped defensively. Purely
    /// informational - never used to decide pantry availability.
    let confidence: Double?
    let explanation: String
    let limitations: String?
    /// On-hand quantity, in the pantry's own unit. `nil` if not in the
    /// pantry.
    let pantryQuantity: Double?
    let pantryUnit: MeasurementUnit?
    let validationStatus: SubstitutionValidationStatus

    init(
        id: UUID = UUID(),
        ingredientName: String,
        suggestedQuantity: Double?,
        suggestedUnit: MeasurementUnit?,
        confidence: Double?,
        explanation: String,
        limitations: String?,
        pantryQuantity: Double?,
        pantryUnit: MeasurementUnit?,
        validationStatus: SubstitutionValidationStatus
    ) {
        self.id = id
        self.ingredientName = ingredientName
        self.suggestedQuantity = suggestedQuantity
        self.suggestedUnit = suggestedUnit
        self.confidence = confidence
        self.explanation = explanation
        self.limitations = limitations
        self.pantryQuantity = pantryQuantity
        self.pantryUnit = pantryUnit
        self.validationStatus = validationStatus
    }

    /// "300 g" style formatting of what's on hand. `nil` if not in the
    /// pantry.
    var formattedPantryQuantity: String? {
        guard let pantryQuantity, let pantryUnit else { return nil }
        return pantryUnit.formatted(pantryQuantity)
    }

    /// "200 ml" style formatting of the suggested amount, if the provider
    /// gave one.
    var formattedSuggestedQuantity: String? {
        guard let suggestedQuantity, let suggestedUnit else { return nil }
        return suggestedUnit.formatted(suggestedQuantity)
    }
}
