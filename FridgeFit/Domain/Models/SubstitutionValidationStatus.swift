//
//  SubstitutionValidationStatus.swift
//  FridgeFit
//

import Foundation

/// The app's own verdict on a substitution suggestion, after checking it
/// against the pantry - never taken from the LLM.
enum SubstitutionValidationStatus: String, Equatable, Codable {
    /// In the pantry, in enough quantity (once safely unit-converted) -
    /// or the suggestion didn't specify an amount, so presence is all
    /// that could be confirmed.
    case availableInPantry
    /// Not in the pantry at all.
    case notInPantry
    /// In the pantry, but not enough of it.
    case insufficientQuantity
    /// In the pantry, but in a unit that can't be safely compared to the
    /// suggested amount.
    case unsupportedUnit
    /// Structurally fine, but conflicts with a stated dietary restriction -
    /// never shown to the user as usable.
    case rejected

    var displayName: String {
        switch self {
        case .availableInPantry: return "In your pantry"
        case .notInPantry: return "Not in pantry"
        case .insufficientQuantity: return "Insufficient quantity"
        case .unsupportedUnit: return "Check amount"
        case .rejected: return "Rejected"
        }
    }

    var symbolName: String {
        switch self {
        case .availableInPantry: return "checkmark.circle.fill"
        case .notInPantry: return "xmark.circle.fill"
        case .insufficientQuantity: return "exclamationmark.triangle.fill"
        case .unsupportedUnit: return "questionmark.circle.fill"
        case .rejected: return "hand.raised.fill"
        }
    }
}
