//
//  AddPantryItemError.swift
//  FridgeFit
//

import Foundation

/// Every way adding a pantry item can fail. Messages are written for the
/// user, not a developer reading a log.
enum AddPantryItemError: LocalizedError, Equatable {
    case emptyIngredientName
    case invalidQuantity
    /// Already in the pantry under this name - see `AddPantryItemUseCase`
    /// for why we reject instead of merging.
    case duplicateIngredient(name: String)

    var errorDescription: String? {
        switch self {
        case .emptyIngredientName:
            return "Please enter an ingredient name so FridgeFit knows what to add."
        case .invalidQuantity:
            return "Quantity must be zero or greater."
        case .duplicateIngredient(let name):
            return "You already have \(name) in your pantry. Update its quantity instead of adding it again."
        }
    }
}
