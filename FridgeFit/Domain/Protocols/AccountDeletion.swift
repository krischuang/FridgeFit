//
//  AccountDeletion.swift
//  FridgeFit
//

import Foundation

/// Removes everything one account owns from one store.
///
/// ## Why this is a protocol and not a method on the repositories
///
/// Deleting an account has to reach stores that no single repository knows
/// about: the pantry, the activity log, saved recipes, five FridgeFunds
/// collections, the remote-camera device registry, WebRTC signalling and its
/// nested candidate subcollections, plus on-device preference and cache
/// files. Adding `deleteEverything()` to `PantryRepository` would put the
/// other eight behind an abstraction that has nothing to do with them, and
/// would let a caller delete a pantry while believing it had deleted an
/// account.
///
/// So each store gets a small conformer, `CompositeAccountDataDeleter`
/// sequences them, and `DeleteAccountUseCase` is the only thing that knows
/// the order matters.
///
/// ## Two rules every conformer must keep
///
/// 1. **Scoped.** Only data owned by `uid` may be touched. Two accounts can
///    share a device, and deleting one must leave the other's pantry intact.
///    This is enforced by `users/{uid}` in Firestore and by an `ownerID`
///    predicate on every local query.
/// 2. **Idempotent.** Deleting data that is already gone must succeed, not
///    throw. That is what makes retry-after-partial-failure safe, and
///    partial failure is the normal case here rather than the exotic one -
///    there is no transaction spanning Firestore, SwiftData and the file
///    system.
protocol AccountDataDeleting {
    /// Removes all data owned by `uid`.
    ///
    /// - Throws: `DeleteAccountError.remoteDataDeletionFailed` or
    ///   `.localDataDeletionFailed`, so the use case can tell the user which
    ///   side of the line the failure fell on without inspecting error
    ///   domains.
    func deleteAllData(ownedBy uid: String) async throws
}

/// The authentication operations account deletion needs.
///
/// Exists so `DeleteAccountUseCase` can be tested without Firebase. The real
/// conformer is `FirebaseAccountAuthenticator`; the tests use a fake that can
/// be told to demand a recent login, reject a password, or fail the delete.
protocol AccountAuthenticating: AnyObject {
    /// The signed-in user's uid, or `nil` if nobody is signed in.
    var currentUID: String? { get }
    /// The signed-in user's email, for the confirmation screen's copy.
    var currentEmail: String? { get }
    /// Which providers this account can prove itself with. Drives whether
    /// the user is asked for a password or sent back through Google.
    var currentProviders: [AccountAuthProvider] { get }

    /// Re-proves the user's identity.
    ///
    /// - Throws: `DeleteAccountError.wrongPassword` or
    ///   `.reauthenticationFailed`.
    func reauthenticate(using method: ReauthenticationMethod) async throws

    /// Deletes the Firebase account.
    ///
    /// - Throws: `DeleteAccountError.reauthenticationRequired` when Firebase
    ///   wants a fresh sign-in first, `.accountDeletionFailed` otherwise.
    func deleteCurrentUser() async throws

    /// Ends the local session.
    func signOut() throws
}

/// Runs several deleters in order, stopping at the first failure.
///
/// ## Why it stops rather than pressing on
///
/// Order is the whole point (see `DeleteAccountUseCase`), and continuing past
/// a failure would mean deleting the device's copy of a pantry whose cloud
/// copy is still there - leaving the account working and apparently empty.
/// Stopping leaves the user with everything they had and a retry that
/// resumes, which is the better of the two wrong states.
struct CompositeAccountDataDeleter: AccountDataDeleting {
    private let stages: [any AccountDataDeleting]

    /// - Parameter stages: run in the order given. Remote before local, so
    ///   the writes that need an auth token happen while there is still one.
    init(stages: [any AccountDataDeleting]) {
        self.stages = stages
    }

    func deleteAllData(ownedBy uid: String) async throws {
        for stage in stages {
            try await stage.deleteAllData(ownedBy: uid)
        }
    }
}
