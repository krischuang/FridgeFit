//
//  FirestoreDiagnosticsTests.swift
//  FridgeFitTests
//

import FirebaseFirestore
import XCTest
@testable import FridgeFit

/// The diagnostics attached to a Firestore failure.
///
/// The bug these exist to prevent: "Missing or insufficient permissions" with
/// no indication of which call was denied, against which path, while signed
/// in as whom. That message cost real debugging time, and the fix is only
/// useful if it keeps carrying the context.
final class FirestoreDiagnosticsTests: XCTestCase {

    private func firestoreError(code: Int, message: String = "Missing or insufficient permissions.") -> NSError {
        NSError(
            domain: FirestoreErrorDomain,
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func failure(
        code: Int,
        message: String = "Missing or insufficient permissions.",
        operation: FirestoreOperation = .listen,
        path: String = "users/abc123def456/devices",
        uid: String? = "abc123def456"
    ) -> FirestoreFailure {
        FirestoreFailure.from(
            firestoreError(code: code, message: message),
            operation: operation,
            path: path,
            uid: uid
        )
    }

    // MARK: - Classification

    func test_permissionDeniedIsRecognised() {
        let failure = failure(code: 7)

        XCTAssertTrue(failure.isPermissionDenied)
        XCTAssertFalse(failure.isUnauthenticated)
        XCTAssertEqual(failure.codeName, "PERMISSION_DENIED")
    }

    func test_unauthenticatedIsRecognised() {
        let failure = failure(code: 16)

        XCTAssertTrue(failure.isUnauthenticated)
        XCTAssertFalse(failure.isPermissionDenied)
        XCTAssertEqual(failure.codeName, "UNAUTHENTICATED")
    }

    func test_knownCodesAreNamed() {
        XCTAssertEqual(failure(code: 5).codeName, "NOT_FOUND")
        XCTAssertEqual(failure(code: 14).codeName, "UNAVAILABLE")
        XCTAssertEqual(failure(code: 8).codeName, "RESOURCE_EXHAUSTED")
    }

    func test_anUnknownFirestoreCodeStillReportsItsNumber() {
        XCTAssertEqual(failure(code: 99).codeName, "FIRESTORE(99)")
    }

    func test_aNonFirestoreErrorReportsItsDomain() {
        let networkError = NSError(domain: NSURLErrorDomain, code: -1009, userInfo: [:])

        let failure = FirestoreFailure.from(
            networkError, operation: .read, path: "users/u/devices/d", uid: "u"
        )

        XCTAssertEqual(failure.codeName, "\(NSURLErrorDomain)(-1009)")
        XCTAssertFalse(failure.isPermissionDenied)
    }

    // MARK: - Context captured

    func test_theOperationAndPathAreCaptured() {
        let failure = failure(code: 7, operation: .create, path: "users/u/webrtcSessions/s/callerCandidates", uid: "u")

        XCTAssertEqual(failure.operation, .create)
        XCTAssertTrue(failure.path.contains("callerCandidates"))
    }

    func test_everyOperationKindHasAWireName() {
        let all: [FirestoreOperation] = [.read, .list, .create, .update, .delete, .listen]
        XCTAssertEqual(Set(all.map(\.rawValue)).count, all.count)
        for operation in all {
            XCTAssertFalse(operation.rawValue.isEmpty)
        }
    }

    func test_authStateIsCaptured() {
        XCTAssertTrue(failure(code: 7, uid: "abc123def456").isSignedIn)
        XCTAssertFalse(failure(code: 7, path: "users/x/devices", uid: nil).isSignedIn)
    }

    // MARK: - Nothing sensitive is logged

    /// The uid is an account identifier. It is useful to correlate two
    /// devices in one log and has no business being there in full.
    func test_theUidIsRedactedFromThePath() {
        let failure = failure(code: 7, path: "users/abc123def456/devices/device-1", uid: "abc123def456")

        XCTAssertEqual(failure.path, "users/{uid}/devices/device-1")
        XCTAssertFalse(failure.path.contains("abc123def456"))
    }

    func test_onlyAShortUidTagIsKept() {
        let failure = failure(code: 7, uid: "abc123def456ghi789")

        XCTAssertEqual(failure.uidTag, "abc123de")
        XCTAssertLessThan(failure.uidTag?.count ?? 99, "abc123def456ghi789".count)
    }

    func test_theDiagnosticSummaryNeverContainsTheFullUid() {
        let uid = "abc123def456ghi789"
        let failure = failure(code: 7, path: "users/\(uid)/devices/device-1", uid: uid)

        XCTAssertFalse(failure.diagnosticSummary.contains(uid))
    }

    func test_theDiagnosticSummaryCarriesEverythingNeededToDebug() {
        let failure = failure(code: 7, operation: .listen, path: "users/u/devices", uid: "u")
        let summary = failure.diagnosticSummary

        XCTAssertTrue(summary.contains("listen"), "operation: \(summary)")
        XCTAssertTrue(summary.contains("devices"), "path: \(summary)")
        XCTAssertTrue(summary.contains("PERMISSION_DENIED"), "code name: \(summary)")
        XCTAssertTrue(summary.contains("7"), "code: \(summary)")
        XCTAssertTrue(summary.contains("signed in"), "auth state: \(summary)")
    }

    func test_signedOutIsCalledOutLoudlyInTheSummary() {
        let failure = failure(code: 16, path: "users/x/devices", uid: nil)

        XCTAssertTrue(failure.diagnosticSummary.contains("SIGNED OUT"))
    }

    // MARK: - What the user is told

    /// The whole point of the fix: a denial names the collections whose rules
    /// need deploying, rather than saying "Missing or insufficient
    /// permissions" and leaving it there.
    func test_permissionDeniedTellsTheUserWhichRulesToDeploy() throws {
        let error = failure(code: 7, operation: .listen, path: "users/u/devices", uid: "u").remoteCameraError

        guard case .signalingUnavailable = error else {
            return XCTFail("expected signalingUnavailable, got \(error)")
        }
        XCTAssertTrue(error.message.contains("users/{uid}/devices"))
        XCTAssertTrue(error.message.contains("webrtcSessions"))
        XCTAssertTrue(error.message.contains("denied"))
    }

    func test_unauthenticatedBecomesNotAuthenticated() {
        XCTAssertEqual(failure(code: 16).remoteCameraError, .notAuthenticated)
    }

    func test_aMissingUidBecomesNotAuthenticatedWhateverTheCode() {
        XCTAssertEqual(
            failure(code: 14, path: "users/x/devices", uid: nil).remoteCameraError,
            .notAuthenticated
        )
    }

    /// A network drop must not tell people to go and redeploy their rules.
    func test_aNetworkFailureDoesNotSuggestDeployingRules() {
        let error = failure(code: 14, message: "The service is currently unavailable.").remoteCameraError

        XCTAssertFalse(error.message.contains("need to be deployed"), error.message)
        XCTAssertTrue(error.message.contains("UNAVAILABLE"), error.message)
        XCTAssertTrue(error.message.contains("listen"), error.message)
    }

    func test_aNonPermissionFailureStillNamesTheOperationAndPath() {
        let error = failure(
            code: 14,
            operation: .create,
            path: "users/u/webrtcSessions/s/calleeCandidates",
            uid: "u"
        ).remoteCameraError

        XCTAssertTrue(error.message.contains("create"), error.message)
        XCTAssertTrue(error.message.contains("calleeCandidates"), error.message)
    }

    // MARK: - Reporting

    func test_reportMapsThroughToTheUserFacingError() {
        let reported = FirestoreDiagnostics.report(
            firestoreError(code: 7),
            operation: .listen,
            path: "users/u/devices",
            uid: "u"
        )

        guard case .signalingUnavailable = reported else {
            return XCTFail("expected signalingUnavailable, got \(reported)")
        }
    }

    func test_performPassesThroughASuccessfulResult() async throws {
        let value = try await FirestoreDiagnostics.perform(
            .read, path: "users/u/devices/d", uid: "u"
        ) {
            42
        }

        XCTAssertEqual(value, 42)
    }

    func test_performWrapsAThrownFirestoreError() async {
        do {
            _ = try await FirestoreDiagnostics.perform(
                .read, path: "users/u/devices/d", uid: "u"
            ) {
                throw self.firestoreError(code: 7)
            }
            XCTFail("expected a throw")
        } catch let error as RemoteCameraError {
            guard case .signalingUnavailable = error else {
                return XCTFail("expected signalingUnavailable, got \(error)")
            }
        } catch {
            XCTFail("expected a RemoteCameraError, got \(error)")
        }
    }

    // MARK: - Signed out

    /// Firestore is never reached while signed out: the registry refuses up
    /// front rather than building a path with a nil uid and letting the
    /// server reject it. That distinction matters because a server rejection
    /// would read as a rules problem.
    func test_theRegistryRefusesBeforeTouchingFirestoreWhenSignedOut() async {
        let registry = FirestoreDeviceRegistry(userIDProvider: { nil })

        do {
            _ = try await registry.fetchDevices()
            XCTFail("expected a throw while signed out")
        } catch let error as RemoteCameraError {
            XCTAssertEqual(error, .notAuthenticated)
        } catch {
            XCTFail("expected notAuthenticated, got \(error)")
        }
    }

    func test_theRegistryRefusesToRegisterWhileSignedOut() async {
        let registry = FirestoreDeviceRegistry(userIDProvider: { nil })
        let identity = DeviceIdentity(deviceId: "device-a", deviceName: "A")

        do {
            try await registry.register(device: identity.asRegisteredDevice(role: .camera))
            XCTFail("expected a throw while signed out")
        } catch let error as RemoteCameraError {
            XCTAssertEqual(error, .notAuthenticated)
        } catch {
            XCTFail("expected notAuthenticated, got \(error)")
        }
    }

    func test_theSignalingTransportRefusesWhileSignedOut() async {
        let transport = FirestoreSignalingTransport(userIDProvider: { nil })

        do {
            _ = try await transport.fetchSession(sessionId: "s1")
            XCTFail("expected a throw while signed out")
        } catch let error as RemoteCameraError {
            XCTAssertEqual(error, .notAuthenticated)
        } catch {
            XCTFail("expected notAuthenticated, got \(error)")
        }
    }

    /// An empty uid is as unusable as a nil one and must not produce the path
    /// `users//devices`.
    func test_anEmptyUidIsTreatedAsSignedOut() async {
        let registry = FirestoreDeviceRegistry(userIDProvider: { "" })

        do {
            _ = try await registry.fetchDevices()
            XCTFail("expected a throw for an empty uid")
        } catch let error as RemoteCameraError {
            XCTAssertEqual(error, .notAuthenticated)
        } catch {
            XCTFail("expected notAuthenticated, got \(error)")
        }
    }

    /// `notAuthenticated` is raised before Firestore is even called, so it
    /// must survive the wrapper rather than being relabelled.
    func test_performLetsARemoteCameraErrorThrough() async {
        do {
            _ = try await FirestoreDiagnostics.perform(
                .read, path: "users/u/devices/d", uid: nil
            ) {
                throw RemoteCameraError.notAuthenticated
            }
            XCTFail("expected a throw")
        } catch let error as RemoteCameraError {
            XCTAssertEqual(error, .notAuthenticated)
        } catch {
            XCTFail("expected a RemoteCameraError, got \(error)")
        }
    }
}
