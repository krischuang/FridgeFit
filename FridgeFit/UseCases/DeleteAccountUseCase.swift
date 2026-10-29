//
//  DeleteAccountUseCase.swift
//  FridgeFit
//

import Foundation

/// Deletes the signed-in FridgeFit account and everything it owns.
///
/// ## The order is the design
///
/// Data first, login last, and that is not a preference - it is forced by
/// Firestore's security model. `firestore.rules` grants access to
/// `users/{uid}/**` only while `request.auth.uid == uid`. Delete the Firebase
/// account first and the client immediately loses the token that authorises
/// it to delete anything underneath that path, so every document the user
/// ever wrote would be stranded: unreachable by them, undeletable by the app,
/// and still sitting in the project. An account deletion that leaves the
/// user's groceries, spending and saved recipes in the cloud is not an
/// account deletion.
///
/// So:
///
/// 1. **Remote data**, while the token is still valid.
/// 2. **Local data**, which needs no token but is cheap to redo.
/// 3. **The Firebase account.**
/// 4. **Sign out**, to clear the session this device is holding.
///
/// ## Partial failure is the expected case, not the exotic one
///
/// There is no transaction spanning Firestore, SwiftData and the file system,
/// so any step can fail with earlier steps already done. Every step is
/// idempotent, so the recovery is simply to run the whole thing again -
/// re-deleting absent data succeeds. The error cases carry *where* it stopped
/// (see `DeleteAccountError`) so the user is told which of "nothing has
/// happened" and "your data is gone but your login isn't" they are in,
/// instead of both being reported as a generic failure.
///
/// ## What this deliberately does not do
///
/// It never reports success unless step 3 returned without throwing. A flow
/// that announced "account deleted" after a failed auth deletion would be
/// the single most misleading thing in the app: the user would believe they
/// were gone while still being able to sign in.
struct DeleteAccountUseCase {
    private let auth: any AccountAuthenticating
    private let data: any AccountDataDeleting
    /// The server-side workflow, when this build has one.
    ///
    /// `nil` is the shipping configuration today: the Cloud Functions in
    /// `functions/` are written and emulator-tested but not deployed, and
    /// pointing the app at a 404 would break the on-device path that does
    /// work. See `AccountDeletionBackendConfiguration`.
    private let backend: (any AccountDeletionBackend)?
    /// Removes this device's copy of the data after the backend has dealt
    /// with the cloud. Only used on the backend path - on the local path the
    /// composite `data` deleter already includes it.
    private let localData: (any AccountDataDeleting)?

    init(
        auth: any AccountAuthenticating,
        data: any AccountDataDeleting,
        backend: (any AccountDeletionBackend)? = nil,
        localData: (any AccountDataDeleting)? = nil
    ) {
        self.auth = auth
        self.data = data
        self.backend = backend
        self.localData = localData
    }

    /// Whether this run will use the server-side workflow.
    var usesBackend: Bool { backend != nil }

    /// Which providers the signed-in account can re-prove itself with.
    var providers: [AccountAuthProvider] {
        auth.currentProviders
    }

    /// The signed-in account's email, for the confirmation copy.
    var accountEmail: String? {
        auth.currentEmail
    }

    /// Deletes the account.
    ///
    /// - Parameter reauthentication: proof of identity to present before
    ///   deleting, when the caller already knows one is needed. `nil` on the
    ///   first attempt - Firebase only demands a fresh sign-in for sessions
    ///   that are old enough, and asking everyone for their password up front
    ///   would be a worse screen for no security gain.
    /// - Throws: `DeleteAccountError`. On
    ///   `.reauthenticationRequired(providers)` the caller should collect the
    ///   matching proof and call this again with it.
    func execute(reauthentication: ReauthenticationMethod? = nil) async throws {
        guard let uid = auth.currentUID, !uid.isEmpty else {
            throw DeleteAccountError.notSignedIn
        }

        if let reauthentication {
            try await auth.reauthenticate(using: reauthentication)
            // The uid must not have changed under us. Reauthenticating into a
            // *different* account and then deleting "this" one would delete
            // the wrong person's data, which is the worst outcome available
            // here, so it is checked rather than assumed.
            guard auth.currentUID == uid else {
                throw DeleteAccountError.reauthenticationFailed(
                    "the sign-in was for a different account"
                )
            }
        }

        if let backend {
            try await deleteThroughBackend(backend, uid: uid)
            return
        }

        // 1 and 2, in that order, inside the composite.
        try await data.deleteAllData(ownedBy: uid)

        // 3. Anything other than a clean return here means the login still
        // exists, and the user is told exactly that.
        try await auth.deleteCurrentUser()

        // 4. Firebase clears `currentUser` on a successful delete, but the
        // local session objects (and Google's) are signed out explicitly so
        // the app returns to the login screen in a known state. A failure
        // here is not worth reporting as a failed deletion - the account is
        // genuinely gone - so it is deliberately swallowed.
        try? auth.signOut()
    }

    /// The server-side path.
    ///
    /// ## Why the client stops doing the cloud work here
    ///
    /// With a backend present, the server owns the Firestore deletion
    /// entirely: it has `recursiveDelete`, a durable job, a write lock, and
    /// the ability to finish after the app is gone. Running the client's
    /// best-effort loop as well would duplicate work and - worse - race the
    /// server's lock, producing permission-denied errors that look like
    /// failures. So on this path the client contributes only the one thing
    /// the server cannot reach: **this device's** SwiftData rows and caches.
    ///
    /// ## Success is the server's word, never an assumption
    ///
    /// `completed` comes from the backend. Anything else - in progress, an
    /// unreadable reply, a timeout - throws, so the sheet cannot show
    /// "account deleted" for a job that has not finished.
    private func deleteThroughBackend(
        _ backend: any AccountDeletionBackend,
        uid: String
    ) async throws {
        let outcome = try await backend.requestDeletion()

        guard outcome.completed, outcome.state == .completed else {
            throw Self.error(for: outcome)
        }

        // The account is gone server-side. Clean this device up; a failure
        // here is reported, because a device still holding the deleted
        // account's pantry is a real privacy problem even though the account
        // itself is gone.
        if let localData {
            try await localData.deleteAllData(ownedBy: uid)
        }

        try? auth.signOut()
    }

    /// Turns a non-completed server outcome into the error that describes it.
    ///
    /// Internal so the mapping is testable without a network.
    static func error(for outcome: RemoteDeletionOutcome) -> DeleteAccountError {
        switch outcome.state {
        case .completed:
            // Reachable only when the server says `completed` but
            // `completed: false` - a contradiction. Treated as unknown
            // rather than resolved in either direction.
            return .deletionStatusUnknown("the server's reply contradicted itself")
        case .pending, .deletingData:
            return .deletionStatusUnknown(
                outcome.lastError ?? "deletion is still in progress"
            )
        case .dataDeleted, .deletingAuth:
            // Data gone, login not. The one state where stopping leaves a
            // working sign-in over an empty account, so it is reported as
            // such and the sheet says so.
            return .accountDeletionFailed(
                outcome.lastError ?? "your data was removed but the sign-in was not"
            )
        case .failed:
            let reason = outcome.lastError ?? "the server could not finish"
            // If the server got as far as emptying the data, say so - the
            // advice differs.
            return outcome.deletedCollections.isEmpty
                ? .remoteDataDeletionFailed(reason)
                : .accountDeletionFailed(reason)
        }
    }
}
