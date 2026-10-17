//
//  UpdatePantryItemError.swift
//  FridgeFit
//

import Foundation

/// The one way updating a pantry item can fail, aside from an invalid
/// quantity (that reuses `AddPantryItemError.invalidQuantity` - same rule).
nonisolated enum UpdatePantryItemError: LocalizedError, Equatable {
    /// Item was removed elsewhere before the update could apply.
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "That ingredient is no longer in your pantry."
        }
    }
}
