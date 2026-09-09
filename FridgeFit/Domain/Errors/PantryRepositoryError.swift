//
//  PantryRepositoryError.swift
//  FridgeFit
//

import Foundation

/// Storage-level failures that aren't specific to one use case.
enum PantryRepositoryError: LocalizedError, Equatable {
    /// No signed-in Firebase user - the pantry is scoped per-user, so
    /// there's nowhere safe to read or write without one.
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You need to be signed in to access your pantry."
        }
    }
}
