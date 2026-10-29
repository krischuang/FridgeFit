//
//  DeleteAccountViewModelTests.swift
//  FridgeFitTests
//
//  The screen's side of account deletion: which phase it is in, what it asks
//  the user for, and what it refuses to do twice.
//

import XCTest
@testable import FridgeFit

@MainActor
final class DeleteAccountViewModelTests: XCTestCase {

    /// `data` defaults to `nil` rather than to a fresh deleter because a
    /// default argument is evaluated outside the actor, and these doubles are
    /// main-actor isolated like the protocols they stand in for.
    private func makeViewModel(
        auth: FakeAccountAuthenticator,
        data: FakeAccountDataDeleter? = nil
    ) -> DeleteAccountViewModel {
        DeleteAccountViewModel(
            useCase: DeleteAccountUseCase(auth: auth, data: data ?? FakeAccountDataDeleter())
        )
    }

    // MARK: - Confirmation

    /// Opening the sheet must delete nothing. The destructive work only
    /// starts when `deleteAccount()` is called, which the view only does from
    /// the confirmation dialog's destructive action.
    func test_initialPhase_isConfirming_andNothingHasBeenDeleted() async {
        let auth = FakeAccountAuthenticator()
        let data = FakeAccountDataDeleter()
        let viewModel = makeViewModel(auth: auth, data: data)

        XCTAssertEqual(viewModel.phase, .confirming)
        XCTAssertTrue(viewModel.canSubmit)
        XCTAssertFalse(viewModel.isDeleting)
        XCTAssertFalse(viewModel.isFinished)
        XCTAssertNil(viewModel.error)
        XCTAssertTrue(data.deletedOwners.isEmpty, "Merely presenting the screen must delete nothing")
        XCTAssertEqual(auth.deleteAttempts, 0)
    }

    /// Cancelling is the absence of a call. Pinned down so a future change
    /// that deletes on `onDisappear` or `.task` is caught.
    func test_cancelling_byNeverCallingDelete_leavesEverythingInPlace() async {
        let auth = FakeAccountAuthenticator()
        let data = FakeAccountDataDeleter()
        _ = makeViewModel(auth: auth, data: data)

        // Simulate the user reading the sheet and dismissing it.
        await Task.yield()

        XCTAssertTrue(data.deletedOwners.isEmpty)
        XCTAssertEqual(auth.deleteAttempts, 0)
        XCTAssertFalse(auth.didSignOut)
    }

    func test_accountEmail_isShownSoTheUserKnowsWhatTheyAreDeleting() async {
        let auth = FakeAccountAuthenticator(email: "cook@example.com")
        XCTAssertEqual(makeViewModel(auth: auth).accountEmail, "cook@example.com")
    }

    // MARK: - Success

    func test_deleteAccount_onSuccess_reachesTheDeletedPhase() async {
        let auth = FakeAccountAuthenticator()
        let data = FakeAccountDataDeleter()
        let viewModel = makeViewModel(auth: auth, data: data)

        await viewModel.deleteAccount()

        XCTAssertEqual(viewModel.phase, .deleted)
        XCTAssertTrue(viewModel.isFinished)
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.canSubmit, "There is nothing left to submit")
        XCTAssertEqual(data.deletedOwners, ["uid-1"])
        XCTAssertTrue(auth.didSignOut)
    }

    /// Success is only reported when the *auth* deletion returned cleanly.
    /// Announcing "account deleted" over a working sign-in would be the most
    /// misleading thing the app could say.
    func test_deleteAccount_whenOnlyTheDataWentAway_doesNotReportDeleted() async {
        let auth = FakeAccountAuthenticator()
        auth.deleteBehaviour = .fail("backend down")
        let viewModel = makeViewModel(auth: auth)

        await viewModel.deleteAccount()

        XCTAssertNotEqual(viewModel.phase, .deleted)
        XCTAssertFalse(viewModel.isFinished)
        XCTAssertEqual(viewModel.error, .accountDeletionFailed("backend down"))
        XCTAssertTrue(viewModel.error?.dataAlreadyDeleted ?? false)
        XCTAssertTrue(viewModel.canSubmit, "The user must be able to finish the job")
    }

    // MARK: - No concurrent attempts

    /// Two deletions racing would mean two `user.delete()` calls, with the
    /// loser reporting a failure for an account that was in fact deleted.
    func test_deleteAccount_whileAlreadyDeleting_doesNotStartASecondAttempt() async {
        let auth = FakeAccountAuthenticator()
        let data = FakeAccountDataDeleter()
        let viewModel = makeViewModel(auth: auth, data: data)

        // Two concurrent taps.
        async let first: Void = viewModel.deleteAccount()
        async let second: Void = viewModel.deleteAccount()
        _ = await (first, second)

        XCTAssertEqual(auth.deleteAttempts, 1, "A second tap must not start a second deletion")
        XCTAssertEqual(data.deletedOwners.count, 1)
        XCTAssertEqual(viewModel.phase, .deleted)
    }

    func test_deleteAccount_afterFinishing_doesNothing() async {
        let auth = FakeAccountAuthenticator()
        let viewModel = makeViewModel(auth: auth)

        await viewModel.deleteAccount()
        await viewModel.deleteAccount()

        XCTAssertEqual(auth.deleteAttempts, 1, "A finished deletion must not be repeated")
    }

    // MARK: - Reauthentication

    func test_whenFirebaseDemandsARecentLogin_theScreenAsksForTheRightProof() async {
        let auth = FakeAccountAuthenticator(providers: [.password])
        auth.deleteBehaviour = .demandRecentLogin
        let viewModel = makeViewModel(auth: auth)

        await viewModel.deleteAccount()

        XCTAssertEqual(viewModel.phase, .needsReauthentication([.password]))
        XCTAssertTrue(viewModel.isAskingForPassword)
        XCTAssertFalse(viewModel.isAskingForGoogle)
        XCTAssertNotNil(viewModel.reauthenticationPrompt)
        XCTAssertFalse(viewModel.canSubmit, "Submit stays disabled until a password is typed")

        viewModel.password = "hunter2"
        XCTAssertTrue(viewModel.canSubmit)
    }

    /// A Google-only account must never be shown a password field - it would
    /// be asking for a credential that has never existed.
    func test_googleOnlyAccount_isNeverAskedForAPassword() async {
        let auth = FakeAccountAuthenticator(providers: [.google])
        auth.deleteBehaviour = .demandRecentLogin
        let viewModel = makeViewModel(auth: auth)

        await viewModel.deleteAccount()

        XCTAssertEqual(viewModel.phase, .needsReauthentication([.google]))
        XCTAssertFalse(viewModel.isAskingForPassword, "There is no password on this account to ask for")
        XCTAssertTrue(viewModel.isAskingForGoogle)
        XCTAssertTrue(viewModel.canSubmit, "Google needs no typed input, so Submit is available")
    }

    func test_reauthenticatingWithAPassword_completesTheDeletion() async {
        let auth = FakeAccountAuthenticator(providers: [.password])
        auth.deleteBehaviour = .demandRecentLoginThenSucceed
        let viewModel = makeViewModel(auth: auth)

        await viewModel.deleteAccount()
        XCTAssertEqual(viewModel.phase, .needsReauthentication([.password]))

        viewModel.password = "hunter2"
        await viewModel.deleteAccount()

        XCTAssertEqual(viewModel.phase, .deleted)
        XCTAssertEqual(auth.reauthentications, [.password("hunter2")])
        XCTAssertTrue(viewModel.password.isEmpty, "The password must not be retained after success")
    }

    func test_reauthenticatingWithGoogle_completesTheDeletion() async {
        let auth = FakeAccountAuthenticator(providers: [.google])
        auth.deleteBehaviour = .demandRecentLoginThenSucceed
        let viewModel = makeViewModel(auth: auth)

        await viewModel.deleteAccount()
        await viewModel.deleteAccount()

        XCTAssertEqual(viewModel.phase, .deleted)
        XCTAssertEqual(auth.reauthentications, [.google])
    }

    func test_aWrongPassword_isReportedAndTheFieldIsCleared() async {
        let auth = FakeAccountAuthenticator(providers: [.password])
        auth.deleteBehaviour = .demandRecentLogin
        let viewModel = makeViewModel(auth: auth)

        await viewModel.deleteAccount()
        viewModel.password = "wrong"
        auth.reauthBehaviour = .wrongPassword
        await viewModel.deleteAccount()

        XCTAssertEqual(viewModel.error, .wrongPassword)
        XCTAssertTrue(viewModel.password.isEmpty, "A rejected password must not be left in the field")
        XCTAssertTrue(viewModel.error?.isRetryable ?? false)
    }

    /// An account whose only provider FridgeFit cannot re-confirm must be
    /// told the truth rather than shown an empty prompt.
    func test_anUnsupportedProvider_reportsThatTheAppCannotDeleteIt() async {
        let auth = FakeAccountAuthenticator(providers: [.other])
        auth.deleteBehaviour = .demandRecentLogin
        let viewModel = makeViewModel(auth: auth)

        await viewModel.deleteAccount()

        XCTAssertEqual(viewModel.error, .noSupportedReauthenticationMethod)
        XCTAssertFalse(viewModel.canSubmit, "Retrying cannot help, so Submit must not invite it")
        XCTAssertFalse(viewModel.isAskingForPassword)
        XCTAssertFalse(viewModel.isAskingForGoogle)
    }

    // MARK: - Partial failure and retry

    func test_aFailedRemoteDeletion_isReportedAsNothingHavingChanged() async {
        let auth = FakeAccountAuthenticator()
        let data = FakeAccountDataDeleter(error: .remoteDataDeletionFailed("offline"))
        let viewModel = makeViewModel(auth: auth, data: data)

        await viewModel.deleteAccount()

        XCTAssertEqual(viewModel.error, .remoteDataDeletionFailed("offline"))
        XCTAssertFalse(viewModel.error?.dataAlreadyDeleted ?? true)
        XCTAssertTrue(viewModel.canSubmit, "Retry is the right next step")
        XCTAssertEqual(auth.deleteAttempts, 0, "The login must be untouched")
    }

    func test_retryingAfterAFailure_succeedsAndClearsTheError() async {
        let auth = FakeAccountAuthenticator()
        let data = FakeAccountDataDeleter(error: .remoteDataDeletionFailed("offline"))
        let viewModel = makeViewModel(auth: auth, data: data)

        await viewModel.deleteAccount()
        XCTAssertNotNil(viewModel.error)

        data.error = nil
        await viewModel.deleteAccount()

        XCTAssertEqual(viewModel.phase, .deleted)
        XCTAssertNil(viewModel.error)
    }

    func test_signedOutDuringTheFlow_reportsNotSignedIn() async {
        let auth = FakeAccountAuthenticator(uid: nil)
        let viewModel = makeViewModel(auth: auth)

        await viewModel.deleteAccount()

        XCTAssertEqual(viewModel.error, .notSignedIn)
        XCTAssertFalse(viewModel.canSubmit, "There is no account to retry deleting")
    }
}
