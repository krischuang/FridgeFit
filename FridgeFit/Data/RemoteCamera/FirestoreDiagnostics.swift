//
//  FirestoreDiagnostics.swift
//  FridgeFit
//

import FirebaseAuth
import FirebaseCore
@preconcurrency import FirebaseFirestore
import Foundation
import OSLog

/// What was being attempted when Firestore refused.
///
/// Firestore's own error carries no notion of *which* call failed, so without
/// this a permission error is just "Missing or insufficient permissions" with
/// no indication of whether it was the device registry, a signaling document
/// or an ICE candidate that was denied.
nonisolated enum FirestoreOperation: String, Sendable {
    case read
    /// A collection query. Worth distinguishing from `read`: rules can allow
    /// `get` and still reject `list`.
    case list
    case create
    case update
    case delete
    /// Attaching a snapshot listener.
    case listen
}

/// A Firestore failure with enough context to act on.
///
/// Deliberately carries no credentials. The signed-in user is reported as a
/// presence flag plus an eight-character tag - enough to tell "the uid in the
/// path isn't the uid we're authenticated as" from "the rules reject us", and
/// not enough to be worth having in a device log.
nonisolated struct FirestoreFailure: Error, Sendable {
    let operation: FirestoreOperation
    /// The collection or document path, with the account's uid replaced by
    /// `{uid}` so the shape is legible without publishing the identifier.
    let path: String
    let code: Int
    let codeName: String
    let message: String
    let isSignedIn: Bool
    /// First eight characters of the authenticated uid, or `nil` when signed
    /// out. Enough to correlate two devices in one log; not the whole value.
    let uidTag: String?
    let projectID: String?

    /// Firestore's `PERMISSION_DENIED`. Almost always a rules problem.
    var isPermissionDenied: Bool { code == 7 }
    /// Firestore's `UNAUTHENTICATED`. The token is missing or expired.
    var isUnauthenticated: Bool { code == 16 }

    /// One line for the log. Safe to print.
    var diagnosticSummary: String {
        let auth = isSignedIn ? "signed in (uid \(uidTag ?? "?")…)" : "SIGNED OUT"
        return """
        Firestore \(operation.rawValue) denied — path: \(path), \
        code: \(code) \(codeName), auth: \(auth), \
        project: \(projectID ?? "unknown"), message: \(message)
        """
    }

    /// What the user is told.
    ///
    /// The "deploy the rules" hint is attached only to `PERMISSION_DENIED`.
    /// Suggesting it for a network drop would send someone to the Firebase
    /// console to fix something that isn't broken.
    var remoteCameraError: RemoteCameraError {
        if isUnauthenticated || !isSignedIn {
            return .notAuthenticated
        }
        if isPermissionDenied {
            return .signalingUnavailable(reason: """
            the request to \(path) was denied. The Firestore security rules \
            for users/{uid}/devices and users/{uid}/webrtcSessions need to be \
            deployed — see docs/webrtc-remote-camera-testing.md
            """)
        }
        return .signalingUnavailable(reason: "\(message) (\(codeName), while trying to \(operation.rawValue) \(path))")
    }

    /// Builds a failure from whatever Firestore threw.
    static func from(
        _ error: Error,
        operation: FirestoreOperation,
        path: String,
        uid: String?
    ) -> FirestoreFailure {
        let nsError = error as NSError
        return FirestoreFailure(
            operation: operation,
            path: redact(path, uid: uid),
            code: nsError.code,
            codeName: codeName(for: nsError),
            message: nsError.localizedDescription,
            isSignedIn: uid != nil,
            uidTag: uid.map { String($0.prefix(8)) },
            projectID: FirebaseApp.app()?.options.projectID
        )
    }

    /// Replaces the account's uid in a path with `{uid}`.
    static func redact(_ path: String, uid: String?) -> String {
        guard let uid, !uid.isEmpty else { return path }
        return path.replacingOccurrences(of: uid, with: "{uid}")
    }

    /// Firestore's gRPC status codes, named. Only the ones this app can
    /// realistically hit are spelled out; anything else reports its number.
    static func codeName(for error: NSError) -> String {
        guard error.domain == FirestoreErrorDomain else {
            return "\(error.domain)(\(error.code))"
        }
        switch error.code {
        case 5: return "NOT_FOUND"
        case 7: return "PERMISSION_DENIED"
        case 8: return "RESOURCE_EXHAUSTED"
        case 14: return "UNAVAILABLE"
        case 16: return "UNAUTHENTICATED"
        default: return "FIRESTORE(\(error.code))"
        }
    }
}

/// Runs Firestore work and turns any failure into a logged `FirestoreFailure`.
///
/// Every Firestore call in the remote-camera feature goes through this, so a
/// denial always arrives with the operation, the path and the auth state
/// attached rather than as a bare "Missing or insufficient permissions".
nonisolated enum FirestoreDiagnostics {
    static let logger = Logger(subsystem: "com.Fridge.FridgeFit", category: "Firestore")

    /// - Parameter path: built with `{uid}` already in place, or with the real
    ///   uid - `FirestoreFailure.redact` removes it either way.
    static func perform<T>(
        _ operation: FirestoreOperation,
        path: @autoclosure () -> String,
        uid: String?,
        work: () async throws -> T
    ) async throws -> T {
        do {
            return try await work()
        } catch let error as RemoteCameraError {
            throw error
        } catch {
            throw report(error, operation: operation, path: path(), uid: uid)
        }
    }

    /// Synchronous counterpart, for snapshot-listener callbacks.
    @discardableResult
    static func report(
        _ error: Error,
        operation: FirestoreOperation,
        path: String,
        uid: String?
    ) -> RemoteCameraError {
        let failure = FirestoreFailure.from(error, operation: operation, path: path, uid: uid)
        if failure.isPermissionDenied || failure.isUnauthenticated {
            logger.error("\(failure.diagnosticSummary, privacy: .public)")
        } else {
            // Network blips are expected and shouldn't read as faults.
            logger.info("\(failure.diagnosticSummary, privacy: .public)")
        }
        return failure.remoteCameraError
    }

    /// The signed-in uid, or `nil`. Read at call time, never cached - the
    /// account can change underneath a long-lived listener.
    static var currentUID: String? {
        Auth.auth().currentUser?.uid
    }
}
