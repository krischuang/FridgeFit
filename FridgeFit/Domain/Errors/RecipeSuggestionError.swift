//
//  RecipeSuggestionError.swift
//  FridgeFit
//

import Foundation

/// Every way suggesting recipes from the pantry can fail. Messages are
/// written for the user - raw `FoundationModels` errors are logged by the
/// provider and mapped onto one of these before they reach the UI.
///
/// Previously these outcomes shared `IngredientRecognitionError` with the
/// fridge-photo scanner, which meant a failed recipe suggestion told the
/// user to "try a clearer, well-lit shot with the fridge door open". The
/// two features now have their own wording.
nonisolated enum RecipeSuggestionError: LocalizedError, Equatable {
    /// Suggestions aren't available - carries the reason so the UI can
    /// explain.
    case suggestionUnavailable(AppleIntelligenceAvailability)
    /// The on-device model ran but its answer couldn't be used.
    case suggestionFailed
    /// The model declined to answer, or the request tripped its safety
    /// guardrails.
    case requestNotAllowed
    /// The model was asked for too much at once, or is busy.
    case modelBusy

    var errorDescription: String? {
        switch self {
        case .suggestionUnavailable(let availability):
            return availability.unavailableExplanation
                ?? "Recipe suggestions aren't available right now."
        case .suggestionFailed:
            return "FridgeFit couldn't come up with recipes from your pantry just now. Please try again."
        case .requestNotAllowed:
            return "FridgeFit couldn't suggest recipes for those ingredients."
        case .modelBusy:
            return "Apple Intelligence is busy right now. Please try again in a moment."
        }
    }
}
