//
//  SaveOnlineRecipeError.swift
//  FridgeFit
//

import Foundation

/// Every way saving an online recipe to the Recipes page - or removing one
/// - can fail. Messages are written for the user.
nonisolated enum SaveOnlineRecipeError: LocalizedError, Equatable {
    /// The recipe has no ingredient lines FridgeFit can check against the
    /// pantry, so saving it would add a recipe that is always "makeable".
    case noUsableIngredients
    /// No signed-in user - saved recipes are stored per user.
    case notAuthenticated
    case saveFailed
    case removeFailed
    case loadFailed

    var errorDescription: String? {
        switch self {
        case .noUsableIngredients:
            return "This recipe doesn't list ingredients FridgeFit can check against your pantry, so it can't be saved."
        case .notAuthenticated:
            return "You need to be signed in to save recipes."
        case .saveFailed:
            return "Couldn't save this recipe. Check your connection and try again."
        case .removeFailed:
            return "Couldn't remove this recipe. Check your connection and try again."
        case .loadFailed:
            return "Couldn't load your saved recipes. Pull to refresh to try again."
        }
    }
}
