//
//  DeleteAccountUseCaseTests.swift
//  FridgeFitTests
//
//  Account deletion is the only irreversible operation in FridgeFit, and the
//  only one where a wrong answer is actively harmful in both directions:
//  reporting success without deleting leaves a user believing they are gone,
//  and deleting the login before the data strands that data forever. Both are
//  pinned down here.
//

import XCTest
@testable import FridgeFit

@MainActor
final class DeleteAccountUseCaseTests: XCTestCase {

    // MARK: - Ordering

    /// The load-bearing rule. Firestore's rules only grant access to
    /// `users/{uid}/**` while `request.auth.uid == uid`, so deleting the
    /// account first would leave every document the user ever wrote
    /// permanently unreachable *and* undeletable.
    func test_execute_deletesDataBeforeTheAccount() async throws {
        let auth = FakeAccountAuthenticator()
        let data = FakeAccountDataDeleter()
        let sut = DeleteAccountUseCase(auth: auth, data: data)

        try await sut.execute()

        XCTAssertEqual(data.deletedOwners, ["uid-1"], "The data must be deleted, for the signed-in uid")
        XCTAssertEqual(auth.deleteAttempts, 1)
        XCTAssertNil(auth.currentUID, "The account itself must be gone")
        XCTAssertTrue(auth.didSignOut)
    }

    /// If the data cannot be removed, the login must be left alone - the user
    /// still has everything, and a retry is safe.
    func test_execute_whenDataDeletionFails_doesNotDeleteTheAccount() async {
        let auth = FakeAccountAuthenticator()
        let data = FakeAccountDataDeleter(error: .remoteDataDeletionFailed("network"))
        let sut = DeleteAccountUseCase(auth: auth, data: data)

        await assertThrowsAsync(try await sut.execute()) { error in
            XCTAssertEqual(error as? DeleteAccountError, .remoteDataDeletionFailed("network"))
        }

        XCTAssertEqual(auth.deleteAttempts, 0, "The login must survive a failed data deletion")
        XCTAssertNotNil(auth.currentUID)
        XCTAssertFalse(auth.didSignOut, "The user must not be signed out of an account that still exists")
    }

    /// The composite runs its stages in order and stops at the first failure,
    /// so a failed cloud deletion does not go on to wipe the device's copy.
    func test_compositeDeleter_runsInOrderAndStopsAtTheFirstFailure() async {
        let log = OrderRecordingDeleter.Log()
        let composite = CompositeAccountDataDeleter(stages: [
            OrderRecordingDeleter(name: "remote", log: log, error: .remoteDataDeletionFailed("denied")),
            OrderRecordingDeleter(name: "local", log: log),
            OrderRecordingDeleter(name: "caches", log: log),
        ])

        await assertThrowsAsync(try await composite.deleteAllData(ownedBy: "uid-1")) { error in
            XCTAssertEqual(error as? DeleteAccountError, .remoteDataDeletionFailed("denied"))
        }

        XCTAssertEqual(log.names, ["remote"], "Later stages must not run after a failure")
    }

    func test_compositeDeleter_runsEveryStage_whenAllSucceed() async throws {
        let log = OrderRecordingDeleter.Log()
        let composite = CompositeAccountDataDeleter(stages: [
            OrderRecordingDeleter(name: "remote", log: log),
            OrderRecordingDeleter(name: "local", log: log),
            OrderRecordingDeleter(name: "caches", log: log),
        ])

        try await composite.deleteAllData(ownedBy: "uid-1")

        XCTAssertEqual(log.names, ["remote", "local", "caches"])
    }

    // MARK: - Not signed in

    func test_execute_whenNobodyIsSignedIn_throwsAndTouchesNothing() async {
        let auth = FakeAccountAuthenticator(uid: nil)
        let data = FakeAccountDataDeleter()
        let sut = DeleteAccountUseCase(auth: auth, data: data)

        await assertThrowsAsync(try await sut.execute()) { error in
            XCTAssertEqual(error as? DeleteAccountError, .notSignedIn)
        }

        XCTAssertTrue(data.deletedOwners.isEmpty, "With no uid there is no scope, so nothing may be deleted")
        XCTAssertEqual(auth.deleteAttempts, 0)
    }

    /// An empty uid is not an owner. Treating it as one would mean a deletion
    /// scoped to `users//...`.
    func test_execute_whenUIDIsEmpty_throwsAndTouchesNothing() async {
        let auth = FakeAccountAuthenticator(uid: "")
        let data = FakeAccountDataDeleter()
        let sut = DeleteAccountUseCase(auth: auth, data: data)

        await assertThrowsAsync(try await sut.execute()) { error in
            XCTAssertEqual(error as? DeleteAccountError, .notSignedIn)
        }
        XCTAssertTrue(data.deletedOwners.isEmpty)
    }

    // MARK: - Reauthentication

    func test_execute_whenFirebaseDemandsARecentLogin_reportsWhichProvidersCanProveIt() async {
        let auth = FakeAccountAuthenticator(providers: [.password])
        auth.deleteBehaviour = .demandRecentLogin
        let sut = DeleteAccountUseCase(auth: auth, data: FakeAccountDataDeleter())

        await assertThrowsAsync(try await sut.execute()) { error in
            XCTAssertEqual(error as? DeleteAccountError, .reauthenticationRequired([.password]))
        }
    }

    /// A Google-only account must be sent back through Google, never asked
    /// for a FridgeFit password it has never had.
    func test_execute_googleOnlyAccount_demandsGoogleNotAPassword() async {
        let auth = FakeAccountAuthenticator(providers: [.google])
        auth.deleteBehaviour = .demandRecentLogin
        let sut = DeleteAccountUseCase(auth: auth, data: FakeAccountDataDeleter())

        await assertThrowsAsync(try await sut.execute()) { error in
            guard case .reauthenticationRequired(let providers) = (error as? DeleteAccountError) else {
                return XCTFail("Expected reauthenticationRequired, got \(error)")
            }
            XCTAssertEqual(providers, [.google])
            XCTAssertFalse(providers.contains(.password), "A Google-only account has no password to ask for")
        }
    }

    func test_execute_withPasswordProof_reauthenticatesThenDeletes() async throws {
        let auth = FakeAccountAuthenticator(providers: [.password])
        auth.deleteBehaviour = .demandRecentLoginThenSucceed
        let data = FakeAccountDataDeleter()
        let sut = DeleteAccountUseCase(auth: auth, data: data)

        // First attempt: Firebase demands a fresh sign-in.
        await assertThrowsAsync(try await sut.execute())

        // Second attempt, with proof.
        try await sut.execute(reauthentication: .password("hunter2"))

        XCTAssertEqual(auth.reauthentications, [.password("hunter2")])
        XCTAssertNil(auth.currentUID)
        XCTAssertTrue(auth.didSignOut)
    }

    func test_execute_withGoogleProof_reauthenticatesThroughGoogle() async throws {
        let auth = FakeAccountAuthenticator(providers: [.google])
        auth.deleteBehaviour = .demandRecentLoginThenSucceed
        let sut = DeleteAccountUseCase(auth: auth, data: FakeAccountDataDeleter())

        await assertThrowsAsync(try await sut.execute())
        try await sut.execute(reauthentication: .google)

        XCTAssertEqual(auth.reauthentications, [.google])
        XCTAssertNil(auth.currentUID)
    }

    func test_execute_withTheWrongPassword_reportsItAndDeletesNothing() async {
        let auth = FakeAccountAuthenticator()
        auth.reauthBehaviour = .wrongPassword
        let data = FakeAccountDataDeleter()
        let sut = DeleteAccountUseCase(auth: auth, data: data)

        await assertThrowsAsync(try await sut.execute(reauthentication: .password("nope"))) { error in
            XCTAssertEqual(error as? DeleteAccountError, .wrongPassword)
        }

        XCTAssertTrue(data.deletedOwners.isEmpty, "A rejected proof must not delete anything")
        XCTAssertEqual(auth.deleteAttempts, 0)
    }

    /// The worst available bug in this flow: reauthenticating into a
    /// different account and then deleting "the" account would destroy the
    /// wrong person's data. The uid is re-checked rather than assumed.
    func test_execute_whenReauthenticationSignsInADifferentAccount_refusesToDelete() async {
        let auth = FakeAccountAuthenticator(uid: "uid-1")
        auth.reauthBehaviour = .succeedAsDifferentAccount(uid: "uid-2")
        let data = FakeAccountDataDeleter()
        let sut = DeleteAccountUseCase(auth: auth, data: data)

        await assertThrowsAsync(try await sut.execute(reauthentication: .password("x"))) { error in
            guard case .reauthenticationFailed = (error as? DeleteAccountError) else {
                return XCTFail("Expected reauthenticationFailed, got \(error)")
            }
        }

        XCTAssertTrue(data.deletedOwners.isEmpty, "No data may be deleted for a mismatched account")
        XCTAssertEqual(auth.deleteAttempts, 0)
    }

    // MARK: - Partial failure and retry

    /// Data gone, login not. The user must be told exactly that, because
    /// stopping here leaves a working sign-in over an empty account.
    func test_execute_whenAccountDeletionFailsAfterDataDeletion_saysSoAndDoesNotSignOut() async {
        let auth = FakeAccountAuthenticator()
        auth.deleteBehaviour = .fail("backend unavailable")
        let data = FakeAccountDataDeleter()
        let sut = DeleteAccountUseCase(auth: auth, data: data)

        await assertThrowsAsync(try await sut.execute()) { error in
            let deleteError = error as? DeleteAccountError
            XCTAssertEqual(deleteError, .accountDeletionFailed("backend unavailable"))
            XCTAssertTrue(deleteError?.dataAlreadyDeleted ?? false, "The copy must warn that data is already gone")
            XCTAssertTrue(deleteError?.isRetryable ?? false)
        }

        XCTAssertEqual(data.deletedOwners, ["uid-1"])
        XCTAssertFalse(auth.didSignOut, "Signing out would hide an account that still exists")
    }

    /// Retrying after a partial failure must finish the job, and re-running
    /// the data stage must be harmless.
    func test_execute_retryAfterPartialFailure_completesTheDeletion() async throws {
        let auth = FakeAccountAuthenticator()
        auth.deleteBehaviour = .fail("transient")
        let data = FakeAccountDataDeleter()
        let sut = DeleteAccountUseCase(auth: auth, data: data)

        await assertThrowsAsync(try await sut.execute())

        auth.deleteBehaviour = .succeed
        try await sut.execute()

        XCTAssertEqual(
            data.deletedOwners,
            ["uid-1", "uid-1"],
            "The data stage runs again on retry, which is safe because every stage is idempotent"
        )
        XCTAssertNil(auth.currentUID)
        XCTAssertTrue(auth.didSignOut)
    }

    /// A sign-out failure must not be reported as a failed deletion. The
    /// account really is gone by then, and reporting a failure would send the
    /// user to retry deleting something that no longer exists.
    func test_execute_whenSignOutFails_stillReportsSuccess() async throws {
        struct Boom: Error {}
        let auth = FakeAccountAuthenticator()
        auth.signOutError = Boom()
        let sut = DeleteAccountUseCase(auth: auth, data: FakeAccountDataDeleter())

        try await sut.execute()

        XCTAssertNil(auth.currentUID, "The account was deleted")
        XCTAssertTrue(auth.didSignOut, "Sign-out was attempted")
    }

    // MARK: - Error copy

    /// Each failure has to say which state the user's data is in, because
    /// "something went wrong" would leave them unable to decide what to do.
    func test_everyError_hasUserFacingCopy_andDistinguishesWhatWasDeleted() {
        let errors: [DeleteAccountError] = [
            .notSignedIn,
            .reauthenticationRequired([.password]),
            .wrongPassword,
            .reauthenticationFailed("reason"),
            .noSupportedReauthenticationMethod,
            .remoteDataDeletionFailed("reason"),
            .localDataDeletionFailed("reason"),
            .accountDeletionFailed("reason"),
        ]

        for error in errors {
            let message = error.localizedDescription
            XCTAssertFalse(message.isEmpty, "\(error) has no message")
            XCTAssertFalse(message.contains("Optional"), "\(error) leaks Swift syntax")
        }

        // Only the post-data failure may claim the data is gone.
        XCTAssertTrue(DeleteAccountError.accountDeletionFailed("x").dataAlreadyDeleted)
        XCTAssertFalse(DeleteAccountError.remoteDataDeletionFailed("x").dataAlreadyDeleted)
        XCTAssertFalse(DeleteAccountError.localDataDeletionFailed("x").dataAlreadyDeleted)

        // "Nothing has happened" has to actually say so, or a user who sees
        // it may assume their data is half-deleted and give up.
        let remote = DeleteAccountError.remoteDataDeletionFailed("offline").localizedDescription
        XCTAssertTrue(
            remote.lowercased().contains("still"),
            "The no-op failure must reassure the user nothing changed, got: \(remote)"
        )

        // A provider FridgeFit cannot re-confirm must not tell the user to
        // try again in the app.
        XCTAssertFalse(DeleteAccountError.noSupportedReauthenticationMethod.isRetryable)
    }

    // MARK: - Provider mapping

    /// Firebase's provider id strings, mapped. `other` exists so an
    /// unrecognised provider fails loudly rather than being treated as a
    /// password account.
    func test_providerMapping_coversFirebasesIDs_andFailsClosed() {
        XCTAssertEqual(FirebaseAccountAuthenticator.provider(forProviderID: "password"), .password)
        XCTAssertEqual(FirebaseAccountAuthenticator.provider(forProviderID: "google.com"), .google)
        XCTAssertEqual(FirebaseAccountAuthenticator.provider(forProviderID: "apple.com"), .other)
        XCTAssertEqual(FirebaseAccountAuthenticator.provider(forProviderID: "phone"), .other)
        XCTAssertEqual(FirebaseAccountAuthenticator.provider(forProviderID: ""), .other)
    }
}
