//
//  RemovePantryItemError.swift
//  FridgeFit
//

import Foundation

/// The one way removing a pantry item can fail.
enum RemovePantryItemError: LocalizedError, Equatable {
    /// Item was already removed by something else before this could run.
    case pantryItemNotFound

    var errorDescription: String? {
        switch self {
        case .pantryItemNotFound:
            return "That ingredient is no longer in your pantry."
        }
    }
}
