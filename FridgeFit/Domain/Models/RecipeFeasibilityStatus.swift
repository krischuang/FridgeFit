//
//  RecipeFeasibilityStatus.swift
//  FridgeFit
//

import Foundation

/// The overall "can I make this?" verdict for a recipe against the
/// current pantry.
///
/// Deliberately just three explainable states, computed from essential
/// ingredient coverage only - optional ingredients never change the
/// verdict. See `EvaluateRecipeFeasibilityUseCase` for the exact rule.
enum RecipeFeasibilityStatus: String, Equatable {
    /// Every essential ingredient is available in sufficient quantity.
    case makeable
    /// At least one essential ingredient is missing or insufficient, but
    /// most of the recipe's essential ingredients are covered.
    case almostMakeable
    /// The majority of essential ingredients are missing or insufficient.
    case notMakeable

    var title: String {
        switch self {
        case .makeable: return "Makeable"
        case .almostMakeable: return "Almost makeable"
        case .notMakeable: return "Not makeable"
        }
    }

    var symbolName: String {
        switch self {
        case .makeable: return "checkmark.circle.fill"
        case .almostMakeable: return "exclamationmark.triangle.fill"
        case .notMakeable: return "xmark.circle.fill"
        }
    }
}
