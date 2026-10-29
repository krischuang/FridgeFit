//
//  AccountDeletionBackendTests.swift
//  FridgeFitTests
//
//  The iOS side of the server-side deletion workflow: decoding the callable
//  reply, mapping every non-completed outcome onto an honest error, and never
//  reporting success the backend did not confirm.
//
//  The transport is exercised against bytes rather than a network, so every
//  branch - including the ones a live server would make hard to produce - is
//  covered deterministically.
//

import OSLog
import XCTest
@testable import FridgeFit

final class CallableAccountDeletionBackendDecodingTests: XCTestCase {

    private func decode(_ json: String, status: Int = 200) throws -> RemoteDeletionOutcome {
        try CallableAccountDeletionBackend.decode(status: status, body: Data(json.utf8))
    }

    // MARK: - Success

    func test_decode_completedJob_reportsCompleted() throws {
        let outcome = try decode(#"""
        {"result":{"state":"completed","completed":true,
         "deletedCollections":["pantry","fundsBudget"],"lastError":null,"attempts":1}}
        """#)

        XCTAssertEqual(outcome.state, .completed)
        XCTAssertTrue(outcome.completed)
        XCTAssertEqual(outcome.deletedCollections, ["pantry", "fundsBudget"])
        XCTAssertEqual(outcome.attempts, 1)
        XCTAssertNil(outcome.lastError)
    }

    /// The server is the authority, but a reply that contradicts itself must
    /// not be resolved in favour of success.
    func test_decode_completedFlagWithoutCompletedState_isNotTreatedAsSuccess() throws {
        let outcome = try decode(#"{"result":{"state":"deletingData","completed":true}}"#)

        XCTAssertFalse(outcome.completed, "a `completed` flag on a running job must not be believed")
        XCTAssertEqual(outcome.state, .deletingData)
    }

    func test_decode_inProgressJob_isNotCompleted() throws {
        for state in ["pending", "deletingData", "dataDeleted", "deletingAuth", "failed"] {
            let outcome = try decode(#"{"result":{"state":"\#(state)","completed":false}}"#)
            XCTAssertFalse(outcome.completed, "\(state) must not report completion")
        }
    }

    // MARK: - Malformed replies

    /// An unrecognised state is reported as unknown rather than guessed at.
    /// Guessing `completed` would be the worst available error.
    func test_decode_unrecognisedState_throwsUnknownRatherThanGuessing() {
        XCTAssertThrowsError(try decode(#"{"result":{"state":"teleported","completed":true}}"#)) { error in
            guard case .deletionStatusUnknown = (error as? DeleteAccountError) else {
                return XCTFail("Expected deletionStatusUnknown, got \(error)")
            }
        }
    }

    func test_decode_missingResultEnvelope_throwsUnknown() {
        XCTAssertThrowsError(try decode(#"{"nonsense":true}"#)) { error in
            guard case .deletionStatusUnknown = (error as? DeleteAccountError) else {
                return XCTFail("Expected deletionStatusUnknown, got \(error)")
            }
        }
    }

    func test_decode_nonJSONBody_throwsUnknown() {
        XCTAssertThrowsError(try decode("<html>502 Bad Gateway</html>")) { error in
            guard case .deletionStatusUnknown = (error as? DeleteAccountError) else {
                return XCTFail("Expected deletionStatusUnknown, got \(error)")
            }
        }
    }

    // MARK: - Error codes

    func test_decode_unauthenticated_becomesNotSignedIn() {
        let body = #"{"error":{"status":"UNAUTHENTICATED","message":"Sign in first."}}"#
        XCTAssertThrowsError(try decode(body, status: 401)) { error in
            XCTAssertEqual(error as? DeleteAccountError, .notSignedIn)
        }
    }

    /// The server's recent-login requirement. Same user-visible meaning as
    /// Firebase's own `requiresRecentLogin`, so the sheet asks for the same
    /// proof rather than showing a dead end.
    func test_decode_failedPrecondition_asksForReauthentication() {
        let body = #"{"error":{"status":"FAILED_PRECONDITION","message":"sign in again"}}"#
        XCTAssertThrowsError(try decode(body, status: 400)) { error in
            guard case .reauthenticationRequired = (error as? DeleteAccountError) else {
                return XCTFail("Expected reauthenticationRequired, got \(error)")
            }
        }
    }

    /// A 404 means the functions are not deployed. That must read as "nothing
    /// was deleted", not as a deletion failure, because nothing was attempted.
    func test_decode_notFound_saysTheServiceIsNotDeployed() {
        XCTAssertThrowsError(try decode(#"{"error":{"status":"NOT_FOUND"}}"#, status: 404)) { error in
            guard case .backendUnreachable(let reason) = (error as? DeleteAccountError) else {
                return XCTFail("Expected backendUnreachable, got \(error)")
            }
            XCTAssertTrue(reason.contains("not deployed"))
        }
        XCTAssertFalse(
            DeleteAccountError.backendUnreachable("x").dataAlreadyDeleted,
            "an unreachable backend has deleted nothing"
        )
    }

    /// A 5xx is genuinely ambiguous - the job may have run. Reporting either
    /// success or failure would be a guess.
    func test_decode_serverError_isReportedAsUnknownNotFailure() {
        XCTAssertThrowsError(try decode(#"{"error":{"status":"INTERNAL"}}"#, status: 500)) { error in
            guard case .deletionStatusUnknown = (error as? DeleteAccountError) else {
                return XCTFail("Expected deletionStatusUnknown, got \(error)")
            }
        }
    }

    func test_decode_permissionDenied_becomesAccountDeletionFailed() {
        let body = #"{"error":{"status":"PERMISSION_DENIED","message":"nope"}}"#
        XCTAssertThrowsError(try decode(body, status: 403)) { error in
            XCTAssertEqual(error as? DeleteAccountError, .accountDeletionFailed("nope"))
        }
    }

    // MARK: - Copy

    /// The two new states have to be distinguishable in words, because the
    /// right next step differs: one means "nothing happened, retry", the
    /// other means "we don't know, go and look".
    func test_theTwoBackendErrors_readDifferently_andNeitherClaimsSuccess() {
        let unreachable = DeleteAccountError.backendUnreachable("offline").localizedDescription
        let unknown = DeleteAccountError.deletionStatusUnknown("timed out").localizedDescription

        XCTAssertNotEqual(unreachable, unknown)
        XCTAssertTrue(unreachable.lowercased().contains("still here"))
        XCTAssertTrue(unknown.lowercased().contains("couldn't confirm"))

        // Neither may make an *affirmative* deletion claim. Checked after
        // stripping the negated forms, because "nothing has been deleted" is
        // precisely the reassurance this copy is supposed to give - a plain
        // substring search would flag the sentence it wants to see.
        let negations = ["nothing has been deleted", "whether your account was deleted"]
        for message in [unreachable, unknown] {
            var claim = message.lowercased()
            for negation in negations {
                claim = claim.replacingOccurrences(of: negation, with: "")
            }
            XCTAssertFalse(claim.contains("has been deleted"), "claims deletion: \(message)")
            XCTAssertFalse(claim.contains("account deleted"), "claims deletion: \(message)")
            XCTAssertFalse(message.contains("Optional"))
        }
    }
}

// MARK: - Outcome → error mapping

final class BackendDeletionOutcomeMappingTests: XCTestCase {

    private func outcome(
        _ state: RemoteDeletionState,
        deleted: [String] = [],
        lastError: String? = nil
    ) -> RemoteDeletionOutcome {
        RemoteDeletionOutcome(
            state: state,
            completed: state == .completed,
            deletedCollections: deleted,
            lastError: lastError
        )
    }

    /// Data gone, login not - the state where stopping leaves a working
    /// sign-in over an empty account. The user has to be told.
    func test_dataDeletedAndDeletingAuth_reportTheDataIsAlreadyGone() {
        for state in [RemoteDeletionState.dataDeleted, .deletingAuth] {
            let error = DeleteAccountUseCase.error(for: outcome(state))
            XCTAssertTrue(
                error.dataAlreadyDeleted,
                "\(state) must warn that the data has already gone"
            )
            XCTAssertTrue(error.isRetryable)
        }
    }

    func test_stillRunning_isReportedAsUnknownNotFailure() {
        for state in [RemoteDeletionState.pending, .deletingData] {
            let error = DeleteAccountUseCase.error(for: outcome(state))
            guard case .deletionStatusUnknown = error else {
                return XCTFail("\(state) should be unknown, got \(error)")
            }
        }
    }

    /// A failure before anything was deleted and a failure part-way through
    /// need different advice, so they map to different errors.
    func test_failedBeforeAnyDeletion_saysNothingWasDeleted() {
        let error = DeleteAccountUseCase.error(for: outcome(.failed, lastError: "permission denied"))

        guard case .remoteDataDeletionFailed(let reason) = error else {
            return XCTFail("Expected remoteDataDeletionFailed, got \(error)")
        }
        XCTAssertEqual(reason, "permission denied")
        XCTAssertFalse(error.dataAlreadyDeleted)
        XCTAssertTrue(error.localizedDescription.contains("still here"))
    }

    func test_failedPartWayThrough_warnsThatDataHasGone() {
        let error = DeleteAccountUseCase.error(
            for: outcome(.failed, deleted: ["pantry"], lastError: "interrupted")
        )

        XCTAssertTrue(error.dataAlreadyDeleted, "some collections were already emptied")
    }

    /// `completed` reaching this function at all means the server's two
    /// fields disagreed. Resolved as unknown, never as success.
    func test_aContradictoryCompletedOutcome_isUnknown() {
        let contradiction = RemoteDeletionOutcome(state: .completed, completed: false)

        guard case .deletionStatusUnknown = DeleteAccountUseCase.error(for: contradiction) else {
            return XCTFail("a contradictory reply must not resolve to success")
        }
    }

    func test_everyRemoteState_mapsToAnErrorWithUserFacingCopy() {
        for state in RemoteDeletionState.allCases {
            let error = DeleteAccountUseCase.error(for: outcome(state))
            XCTAssertFalse(error.localizedDescription.isEmpty, "\(state) has no message")
        }
    }
}

// MARK: - Contract with the TypeScript backend

final class AccountDeletionBackendContractTests: XCTestCase {

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        // .../FridgeFitTests/Account/AccountDeletionBackendTests.swift
        for _ in 0 ..< 3 { url.deleteLastPathComponent() }
        return url
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: Self.repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// A state the server can report and the client cannot decode would
    /// surface as `deletionStatusUnknown` for a deletion that is actually
    /// progressing normally. The two enums are kept in step here rather than
    /// by memory.
    func test_everyServerState_isDecodableByTheClient() throws {
        let typescript = try source("functions/src/deletion.ts")

        // The `DeletionState` union members, written as `| "name"`.
        let pattern = #"\|\s*"([a-zA-Z]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(typescript.startIndex..., in: typescript)
        var serverStates: Set<String> = []
        for match in regex.matches(in: typescript, range: range) {
            guard let r = Range(match.range(at: 1), in: typescript) else { continue }
            serverStates.insert(String(typescript[r]))
        }

        XCTAssertFalse(serverStates.isEmpty, "the DeletionState parse found nothing")

        let clientStates = Set(RemoteDeletionState.allCases.map(\.rawValue))
        XCTAssertEqual(
            serverStates.subtracting(clientStates),
            [],
            "the server can report states the client cannot decode"
        )
    }

    /// The client must not send a uid. The server ignores one, but sending it
    /// would imply the server trusts it, and someone reading the client would
    /// reasonably conclude the endpoint is uid-addressed.
    func test_theClientSendsNoUidOrPath() throws {
        let swift = try source("FridgeFit/Data/CallableAccountDeletionBackend.swift")

        XCTAssertTrue(
            swift.contains(##"Data(#"{"data":{}}"#.utf8)"##),
            "the request body should be an empty callable envelope"
        )
        for forbidden in ["\"uid\":", "\"userId\":", "\"path\":"] {
            XCTAssertFalse(swift.contains(forbidden), "the client sends \(forbidden)")
        }
    }

    /// The backend is deliberately off in the shipping build, because the
    /// functions are not deployed and a 404 would break the working
    /// on-device path.
    func test_theBackendIsDisabledByDefault() {
        XCTAssertNil(
            AccountDeletionBackendConfiguration.compiledDefault,
            "enabling this requires the Cloud Functions to be deployed first"
        )
    }

    /// ...but it can be switched on for a run without a rebuild, which is how
    /// the emulator is pointed at.
    func test_aLaunchArgumentCanPointTheAppAtAnEmulator() {
        let defaults = UserDefaults.standard
        let key = "accountDeletionBackend"
        let original = defaults.string(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) } else { defaults.removeObject(forKey: key) }
        }

        defaults.set("http://127.0.0.1:5401/demo-fridgefit/us-central1", forKey: key)

        XCTAssertEqual(
            AccountDeletionBackendConfiguration.baseURL?.absoluteString,
            "http://127.0.0.1:5401/demo-fridgefit/us-central1"
        )
        XCTAssertTrue(AccountDeletionBackendConfiguration.isEnabled)
    }

    /// The region in the Swift config and in `setGlobalOptions` must match,
    /// or the client would build a URL for a function that is not there.
    func test_theRegionMatchesTheFunctionsConfiguration() throws {
        let typescript = try source("functions/src/index.ts")

        XCTAssertTrue(
            typescript.contains("region: \"\(AccountDeletionBackendConfiguration.region)\""),
            "the client region does not match setGlobalOptions"
        )
    }

    /// Both callable names the client calls must actually be exported.
    func test_bothCallableNamesExistOnTheServer() throws {
        let typescript = try source("functions/src/index.ts")

        for name in ["requestAccountDeletion", "accountDeletionStatus"] {
            XCTAssertTrue(
                typescript.contains("export const \(name) = onCall"),
                "\(name) is not exported as a callable"
            )
        }
    }
}
