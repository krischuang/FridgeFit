//
//  IngredientRecognitionError.swift
//  FridgeFit
//

import Foundation

/// Every way scanning a fridge photo can fail. Messages are written for the
/// user - raw `FoundationModels` / `Vision` errors are logged by the
/// provider and mapped onto one of these before they reach the UI.
nonisolated enum IngredientRecognitionError: LocalizedError, Equatable {
    /// Analyze was triggered with nothing selected.
    case noImageSelected
    /// The picked photo couldn't be turned into something analysable.
    case invalidImage
    /// Scanning isn't available - carries the reason so the UI can explain.
    case recognitionUnavailable(IngredientRecognitionAvailability)
    /// The on-device model ran but its answer couldn't be used.
    case recognitionFailed
    /// The model declined to answer, or the request tripped its safety
    /// guardrails.
    case requestNotAllowed
    /// The model was asked for too much at once, or is busy.
    case modelBusy
    /// The image analysed fine, there just wasn't any recognisable food.
    case noIngredientsDetected

    var errorDescription: String? {
        switch self {
        case .noImageSelected:
            return "Choose or take a photo of your fridge first."
        case .invalidImage:
            return "That photo couldn't be read. Try taking another one."
        case .recognitionUnavailable(let availability):
            return availability.unavailableExplanation
                ?? "Fridge scanning isn't available right now."
        case .recognitionFailed:
            return "FridgeFit couldn't work out what's in that photo. Try a clearer, well-lit shot with the fridge door open."
        case .requestNotAllowed:
            return "FridgeFit couldn't analyse that photo. Try a different photo of your fridge."
        case .modelBusy:
            return "Apple Intelligence is busy right now. Please try again in a moment."
        case .noIngredientsDetected:
            return "No ingredients were recognised in that photo. Try getting closer, with the fridge door open and the light on."
        }
    }
}
