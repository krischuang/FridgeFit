//
//  BackendDeleteAccountUseCaseTests.swift
//  FridgeFitTests
//
//  `DeleteAccountUseCase` when a server-side backend is configured.
//
//  The contract being pinned down: the app reports success only when the
//  backend confirms it, the client stops duplicating the cloud work, and
//  this device's own copy is still cleaned up.
//

import XCTest
@testable import FridgeFit

/// A scriptable `AccountDeletionBackend`.
@MainActor
final class FakeAccountDeletionBackend: AccountDeletionBackend {
    var requestResult: Result<RemoteDeletionOutcome, Error>
    var statusResult: Result<RemoteDeletionOutcome, Error>
    private(set) var requestCount = 0
    private(set) var statusCount = 0

    init(
        requestResult: Result<RemoteDeletionOutcome, Error> = .success(
            RemoteDeletionOutcome(state: .completed, completed: true)
        ),
        statusResult: Result<RemoteDeletionOutcome, Error>? = nil
    ) {
        self.requestResult = requestResult
        self.statusResult = statusResult ?? requestResult
    }

    func requestDeletion() async throws -> RemoteDeletionOutcome {
        requestCount += 1
        return try requestResult.get()
    }

    func deletionStatus() async throws -> RemoteDeletionOutcome {
        statusCount += 1
        return try statusResult.get()
    }
}

@MainActor
final class BackendDeleteAccountUseCaseTests: XCTestCase {

    private func makeUseCase(
        auth: FakeAccountAuthenticator,
        backend: FakeAccountDeletionBackend,
        cloudData: FakeAccountDataDeleter? = nil,
        localData: FakeAccountDataDeleter? = nil
    ) -> DeleteAccountUseCase {
        DeleteAccountUseCase(
            auth: auth,
            data: cloudData ?? FakeAccountDataDeleter(),
            backend: backend,
            localData: localData ?? FakeAccountDataDeleter()
        )
    }

    // MARK: - Success

    func test_backendConfirmsCompletion_deletesLocalDataAndSignsOut() async throws {
        let auth = FakeAccountAuthenticator()
        let backend = FakeAccountDeletionBackend()
        let local = FakeAccountDataDeleter()
        let sut = makeUseCase(auth: auth, backend: backend, localData: local)

        try await sut.execute()

        XCTAssertEqual(backend.requestCount, 1)
        XCTAssertEqual(local.deletedOwners, ["uid-1"], "this device's copy must still be removed")
        XCTAssertTrue(auth.didSignOut)
    }

    /// With a backend present the client must not also run its own Firestore
    /// loop: it would duplicate the work and race the server's write lock,
    /// producing permission-denied errors that look like failures.
    func test_withABackend_theClientDoesNotRunItsOwnCloudDeletion() async throws {
        let cloud = FakeAccountDataDeleter()
        let sut = makeUseCase(
            auth: FakeAccountAuthenticator(),
            backend: FakeAccountDeletionBackend(),
            cloudData: cloud
        )

        try await sut.execute()

        XCTAssertTrue(cloud.deletedOwners.isEmpty, "the client duplicated the server's work")
    }

    /// The server deletes the auth account itself, so the client must not
    /// also call `user.delete()` - it would fail on an account that is
    /// already gone and be reported as a failure.
    func test_withABackend_theClientDoesNotDeleteTheAuthAccountItself() async throws {
        let auth = FakeAccountAuthenticator()
        let sut = makeUseCase(auth: auth, backend: FakeAccountDeletionBackend())

        try await sut.execute()

        XCTAssertEqual(auth.deleteAttempts, 0, "the server owns the auth deletion")
    }

    func test_usesBackend_reflectsWhetherOneIsConfigured() {
        let withBackend = makeUseCase(
            auth: FakeAccountAuthenticator(),
            backend: FakeAccountDeletionBackend()
        )
        XCTAssertTrue(withBackend.usesBackend)

        let without = DeleteAccountUseCase(
            auth: FakeAccountAuthenticator(),
            data: FakeAccountDataDeleter()
        )
        XCTAssertFalse(without.usesBackend)
    }

    // MARK: - Never report unconfirmed success

    /// The headline requirement: no "account deleted" without the backend
    /// saying so.
    func test_aJobStillInProgress_throwsRatherThanReportingSuccess() async {
        for state in [RemoteDeletionState.pending, .deletingData] {
            let local = FakeAccountDataDeleter()
            let auth = FakeAccountAuthenticator()
            let sut = makeUseCase(
                auth: auth,
                backend: FakeAccountDeletionBackend(
                    requestResult: .success(RemoteDeletionOutcome(state: state, completed: false))
                ),
                localData: local
            )

            await assertThrowsAsync(try await sut.execute(), "\(state) must not report success") { error in
                guard case .deletionStatusUnknown = (error as? DeleteAccountError) else {
                    return XCTFail("Expected deletionStatusUnknown for \(state), got \(error)")
                }
            }

            XCTAssertTrue(
                local.deletedOwners.isEmpty,
                "\(state): local data must not be wiped for an unconfirmed deletion"
            )
            XCTAssertFalse(auth.didSignOut, "\(state): the user must not be signed out")
        }
    }

    /// Data gone, login not. The user has to be told, and this device's copy
    /// must not be destroyed on the strength of a half-finished job.
    func test_dataDeletedButAccountAlive_reportsThatTheDataHasAlreadyGone() async {
        let local = FakeAccountDataDeleter()
        let sut = makeUseCase(
            auth: FakeAccountAuthenticator(),
            backend: FakeAccountDeletionBackend(
                requestResult: .success(
                    RemoteDeletionOutcome(state: .dataDeleted, completed: false, lastError: "interrupted")
                )
            ),
            localData: local
        )

        await assertThrowsAsync(try await sut.execute()) { error in
            let deleteError = error as? DeleteAccountError
            XCTAssertEqual(deleteError, .accountDeletionFailed("interrupted"))
            XCTAssertTrue(deleteError?.dataAlreadyDeleted ?? false)
            XCTAssertTrue(deleteError?.isRetryable ?? false)
        }
        XCTAssertTrue(local.deletedOwners.isEmpty)
    }

    func test_aFailedJob_propagatesTheServersReason() async {
        let sut = makeUseCase(
            auth: FakeAccountAuthenticator(),
            backend: FakeAccountDeletionBackend(
                requestResult: .success(
                    RemoteDeletionOutcome(state: .failed, completed: false, lastError: "quota exceeded")
                )
            )
        )

        await assertThrowsAsync(try await sut.execute()) { error in
            XCTAssertEqual(error as? DeleteAccountError, .remoteDataDeletionFailed("quota exceeded"))
        }
    }

    // MARK: - Transport failures

    func test_anUnreachableBackend_reportsThatNothingWasDeleted() async {
        let local = FakeAccountDataDeleter()
        let auth = FakeAccountAuthenticator()
        let sut = makeUseCase(
            auth: auth,
            backend: FakeAccountDeletionBackend(
                requestResult: .failure(DeleteAccountError.backendUnreachable("offline"))
            ),
            localData: local
        )

        await assertThrowsAsync(try await sut.execute()) { error in
            XCTAssertEqual(error as? DeleteAccountError, .backendUnreachable("offline"))
            XCTAssertFalse((error as? DeleteAccountError)?.dataAlreadyDeleted ?? true)
        }

        XCTAssertTrue(local.deletedOwners.isEmpty, "nothing may be deleted when nothing was attempted")
        XCTAssertFalse(auth.didSignOut)
    }

    /// A timeout is ambiguous, so it must not be reported as either outcome.
    func test_aTimeout_isReportedAsUnknownNotFailure() async {
        let sut = makeUseCase(
            auth: FakeAccountAuthenticator(),
            backend: FakeAccountDeletionBackend(
                requestResult: .failure(DeleteAccountError.deletionStatusUnknown("timed out"))
            )
        )

        await assertThrowsAsync(try await sut.execute()) { error in
            guard case .deletionStatusUnknown = (error as? DeleteAccountError) else {
                return XCTFail("Expected deletionStatusUnknown, got \(error)")
            }
        }
    }

    // MARK: - Authorization still applies on the client

    func test_signedOut_neverReachesTheBackend() async {
        let backend = FakeAccountDeletionBackend()
        let sut = makeUseCase(auth: FakeAccountAuthenticator(uid: nil), backend: backend)

        await assertThrowsAsync(try await sut.execute()) { error in
            XCTAssertEqual(error as? DeleteAccountError, .notSignedIn)
        }
        XCTAssertEqual(backend.requestCount, 0, "a signed-out request must not be sent")
    }

    /// Provider-aware reauthentication is unchanged by the backend: it still
    /// happens on the client, before anything is sent.
    func test_reauthenticationStillHappensBeforeTheBackendIsCalled() async throws {
        let auth = FakeAccountAuthenticator(providers: [.google])
        let backend = FakeAccountDeletionBackend()
        let sut = makeUseCase(auth: auth, backend: backend)

        try await sut.execute(reauthentication: .google)

        XCTAssertEqual(auth.reauthentications, [.google])
        XCTAssertEqual(backend.requestCount, 1)
    }

    func test_aRejectedReauthentication_neverReachesTheBackend() async {
        let auth = FakeAccountAuthenticator()
        auth.reauthBehaviour = .wrongPassword
        let backend = FakeAccountDeletionBackend()
        let sut = makeUseCase(auth: auth, backend: backend)

        await assertThrowsAsync(try await sut.execute(reauthentication: .password("nope"))) { error in
            XCTAssertEqual(error as? DeleteAccountError, .wrongPassword)
        }
        XCTAssertEqual(backend.requestCount, 0)
    }

    /// Reauthenticating into a *different* account must still be caught
    /// before anything is deleted - the backend would otherwise happily
    /// delete whoever the new token belongs to.
    func test_reauthenticatingAsADifferentAccount_neverReachesTheBackend() async {
        let auth = FakeAccountAuthenticator(uid: "uid-1")
        auth.reauthBehaviour = .succeedAsDifferentAccount(uid: "uid-2")
        let backend = FakeAccountDeletionBackend()
        let sut = makeUseCase(auth: auth, backend: backend)

        await assertThrowsAsync(try await sut.execute(reauthentication: .password("x"))) { error in
            guard case .reauthenticationFailed = (error as? DeleteAccountError) else {
                return XCTFail("Expected reauthenticationFailed, got \(error)")
            }
        }
        XCTAssertEqual(backend.requestCount, 0, "the wrong account would have been deleted")
    }

    // MARK: - Retry

    func test_retryingAfterAnUnknownOutcome_succeedsWhenTheJobFinishes() async throws {
        let auth = FakeAccountAuthenticator()
        let backend = FakeAccountDeletionBackend(
            requestResult: .success(RemoteDeletionOutcome(state: .deletingData, completed: false))
        )
        let local = FakeAccountDataDeleter()
        let sut = makeUseCase(auth: auth, backend: backend, localData: local)

        await assertThrowsAsync(try await sut.execute())

        backend.requestResult = .success(RemoteDeletionOutcome(state: .completed, completed: true))
        try await sut.execute()

        XCTAssertEqual(backend.requestCount, 2)
        XCTAssertEqual(local.deletedOwners, ["uid-1"])
        XCTAssertTrue(auth.didSignOut)
    }

    /// A local cleanup failure after a confirmed cloud deletion is reported,
    /// not swallowed: a device still holding the deleted account's pantry is
    /// a real privacy problem even though the account itself is gone.
    func test_aLocalCleanupFailure_isReportedEvenThoughTheAccountIsGone() async {
        let local = FakeAccountDataDeleter(error: .localDataDeletionFailed("disk full"))
        let sut = makeUseCase(
            auth: FakeAccountAuthenticator(),
            backend: FakeAccountDeletionBackend(),
            localData: local
        )

        await assertThrowsAsync(try await sut.execute()) { error in
            XCTAssertEqual(error as? DeleteAccountError, .localDataDeletionFailed("disk full"))
        }
    }
}
