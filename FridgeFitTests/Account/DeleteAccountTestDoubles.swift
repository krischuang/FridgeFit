//
//  DeleteAccountTestDoubles.swift
//  FridgeFitTests
//

import Foundation
@testable import FridgeFit

/// A scriptable `AccountAuthenticating`.
///
/// Firebase cannot be driven into `requiresRecentLogin`, a wrong password or
/// a failed delete from a unit test, and account deletion is the one
/// operation where those branches must not be taken on trust - getting them
/// wrong either strands a user's data or tells them they are deleted when
/// they are not. So every branch is scripted here.
@MainActor
final class FakeAccountAuthenticator: AccountAuthenticating {

    /// What `deleteCurrentUser()` should do.
    enum DeleteBehaviour {
        case succeed
        /// Firebase wants a fresh sign-in first.
        case demandRecentLogin
        case fail(String)
        /// Demand a recent login the first time, then succeed. The real
        /// sequence a user with an old session goes through.
        case demandRecentLoginThenSucceed
    }

    /// What `reauthenticate(using:)` should do.
    enum ReauthBehaviour {
        case succeed
        case wrongPassword
        case fail(String)
        /// Succeeds, but leaves a *different* account signed in - the
        /// scenario that would otherwise delete the wrong person's data.
        case succeedAsDifferentAccount(uid: String)
    }

    var currentUID: String?
    var currentEmail: String?
    var currentProviders: [AccountAuthProvider]

    var deleteBehaviour: DeleteBehaviour = .succeed
    var reauthBehaviour: ReauthBehaviour = .succeed
    /// Thrown from `signOut()`. The account is genuinely gone by then, so a
    /// failure here must not be reported as a failed deletion.
    var signOutError: Error?

    private(set) var deleteAttempts = 0
    private(set) var reauthentications: [ReauthenticationMethod] = []
    private(set) var didSignOut = false

    init(
        uid: String? = "uid-1",
        email: String? = "cook@example.com",
        providers: [AccountAuthProvider] = [.password]
    ) {
        self.currentUID = uid
        self.currentEmail = email
        self.currentProviders = providers
    }

    func reauthenticate(using method: ReauthenticationMethod) async throws {
        reauthentications.append(method)
        switch reauthBehaviour {
        case .succeed:
            break
        case .wrongPassword:
            throw DeleteAccountError.wrongPassword
        case .fail(let reason):
            throw DeleteAccountError.reauthenticationFailed(reason)
        case .succeedAsDifferentAccount(let uid):
            currentUID = uid
        }
    }

    func deleteCurrentUser() async throws {
        deleteAttempts += 1
        guard currentUID != nil else { throw DeleteAccountError.notSignedIn }

        switch deleteBehaviour {
        case .succeed:
            currentUID = nil
        case .demandRecentLogin:
            throw DeleteAccountError.reauthenticationRequired(currentProviders)
        case .fail(let reason):
            throw DeleteAccountError.accountDeletionFailed(reason)
        case .demandRecentLoginThenSucceed:
            if deleteAttempts == 1 {
                throw DeleteAccountError.reauthenticationRequired(currentProviders)
            }
            currentUID = nil
        }
    }

    func signOut() throws {
        didSignOut = true
        if let signOutError { throw signOutError }
    }
}

/// A recording `AccountDataDeleting` that can be told to fail.
@MainActor
final class FakeAccountDataDeleter: AccountDataDeleting {
    /// Every uid this was asked to delete, so a test can prove the *right*
    /// account was targeted and that a retry is idempotent.
    private(set) var deletedOwners: [String] = []
    var error: DeleteAccountError?

    init(error: DeleteAccountError? = nil) {
        self.error = error
    }

    func deleteAllData(ownedBy uid: String) async throws {
        deletedOwners.append(uid)
        if let error { throw error }
    }
}

/// Records the order several stages ran in, for the composite's ordering
/// guarantee.
@MainActor
final class OrderRecordingDeleter: AccountDataDeleting {
    private let name: String
    private let log: Log
    private let error: DeleteAccountError?

    @MainActor
    final class Log {
        private(set) var names: [String] = []
        func append(_ name: String) { names.append(name) }
    }

    init(name: String, log: Log, error: DeleteAccountError? = nil) {
        self.name = name
        self.log = log
        self.error = error
    }

    func deleteAllData(ownedBy uid: String) async throws {
        log.append(name)
        if let error { throw error }
    }
}
