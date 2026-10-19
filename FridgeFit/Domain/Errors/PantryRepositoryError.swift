//
//  PantryRepositoryError.swift
//  FridgeFit
//

import Foundation

/// Storage-level failures that aren't specific to one use case.
nonisolated enum PantryRepositoryError: LocalizedError, Equatable {
    /// No signed-in Firebase user - the pantry is scoped per-user, so
    /// there's nowhere safe to read or write without one.
    case notAuthenticated

    /// The store itself could not be read or written.
    ///
    /// Raised by `SwiftDataPantryRepository` in place of SwiftData's own
    /// error types, so a use case or view model never has to pattern match
    /// on a storage framework to decide what to tell the user. Deliberately
    /// carries no underlying detail: the message is for someone looking at
    /// their pantry, and a `CoreData` error code is not.
    case storageUnavailable

    /// No repository was injected into this part of the view tree.
    ///
    /// A programmer error, surfaced as an error rather than a crash or - far
    /// worse - a silent write to whichever backend a default happened to
    /// construct. See `UnconfiguredPantryRepository`.
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You need to be signed in to access your pantry."
        case .notConfigured:
            return "FridgeFit couldn't reach your pantry from this screen. Close it and try again."
        case .storageUnavailable:
            return "FridgeFit couldn't open your pantry on this device. Try again, and if it keeps happening, restart the app."
        }
    }
}
