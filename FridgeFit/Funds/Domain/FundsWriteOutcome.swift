//
//  FundsWriteOutcome.swift
//  FridgeFit
//

import Foundation

/// What actually happened to a FridgeFunds write.
///
/// ## Why "saved" is not a boolean
///
/// The stores used to return `Void` from every write and apply the change to
/// their in-memory copy immediately, so the Impact screen said "saved" the
/// instant the user tapped Save. For the on-device store that is true. For
/// Firestore it was not: `setData`'s completion handler fires when the
/// **server** acknowledges the write, and the previous code passed a handler
/// that only logged, so a permission-denied or unauthenticated write
/// disappeared into the console while the user was looking at a budget the
/// backend had refused.
///
/// Fixing that by awaiting the acknowledgement is correct but not
/// sufficient, because of how Firestore behaves offline: it persists the
/// write to a durable local queue and reports it to listeners right away, but
/// does **not** call the completion handler until it reaches the server,
/// which may be hours later. An `await` with no bound would therefore hang
/// the Save button for the entire time a user was on the Underground.
///
/// Neither "saved" nor "failed" describes that state, so there is a third
/// one. The distinction the UI needs is exactly:
///
/// - `committed` - the server has it. Durable everywhere.
/// - `pendingSync` - this device has it, durably, and Firestore will deliver
///   it. Not lost, not yet confirmed.
/// - a thrown error - it is not saved anywhere, and the local copy has been
///   rolled back.
nonisolated enum FundsWriteOutcome: Equatable, Sendable {
    /// Durably stored and acknowledged by whatever is authoritative - the
    /// server in Firebase mode, the local database in SwiftData mode.
    case committed

    /// Written to Firestore's durable offline queue and applied locally, but
    /// not yet acknowledged by the server.
    ///
    /// Only Firestore ever returns this. A local store has no second place
    /// for the data to arrive at, so it is always `committed`.
    case pendingSync

    /// Whether the user can be told their change is safely stored.
    ///
    /// True for both cases: a queued Firestore write survives app relaunch,
    /// so it is not at risk - it is just not confirmed. The wording differs
    /// (`statusDescription`), the reassurance does not.
    var isDurable: Bool { true }

    /// What to tell the user, or `nil` when there is nothing worth saying -
    /// a committed write needs no announcement beyond the number changing on
    /// screen.
    var statusDescription: String? {
        switch self {
        case .committed:
            return nil
        case .pendingSync:
            return "Saved on this device. It'll sync when you're back online."
        }
    }
}
