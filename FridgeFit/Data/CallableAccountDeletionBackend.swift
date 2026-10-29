//
//  CallableAccountDeletionBackend.swift
//  FridgeFit
//

import FirebaseAuth
import Foundation
import OSLog

/// Whether this build has a deletion backend, and where it is.
///
/// ## Why this defaults to off
///
/// The Cloud Functions in `functions/` are written, compiled and tested
/// against the Local Emulator Suite, but **they are not deployed**. Deploying
/// them requires the Blaze (pay-as-you-go) plan on the live Firebase project,
/// which is an explicit billing decision and not one to take on a
/// maintainer's behalf.
///
/// Pointing the shipping app at an endpoint that returns 404 would break the
/// one thing that currently works - the on-device deletion path, which is
/// fully tested and does remove the user's data. So the backend is wired,
/// tested and ready, and off.
///
/// Turning it on is a one-line change plus a deploy; see
/// `docs/assessment4-final-production-verification.md`. Everything below the
/// flag is exercised by `CallableAccountDeletionBackendTests` regardless, so
/// enabling it is not a leap of faith.
nonisolated enum AccountDeletionBackendConfiguration {

    /// The Cloud Functions region, matching `setGlobalOptions` in
    /// `functions/src/index.ts`.
    static let region = "us-central1"

    /// The Firebase project the functions would be deployed to.
    static let projectID = "fridgefit-app"

    /// Resolution order:
    /// 1. A `-accountDeletionBackend <url>` launch argument, so the emulator
    ///    suite and a demo can point the app at `127.0.0.1` without a
    ///    rebuild.
    /// 2. `compiledDefault`.
    static var baseURL: URL? {
        if let override = UserDefaults.standard.string(forKey: "accountDeletionBackend"),
           let url = URL(string: override) {
            return url
        }
        return compiledDefault
    }

    /// `nil` means "no backend": the app uses the on-device deletion path.
    ///
    /// Change to
    /// `URL(string: "https://us-central1-fridgefit-app.cloudfunctions.net")`
    /// after deploying the functions.
    static let compiledDefault: URL? = nil

    /// Whether a backend is configured for this run.
    static var isEnabled: Bool { baseURL != nil }
}

/// Talks to the `requestAccountDeletion` / `accountDeletionStatus` callable
/// functions.
///
/// ## Why URLSession rather than the Functions SDK
///
/// `FirebaseFunctions` is not linked into this target, and adding it would
/// pull a new product into the project for one endpoint. Callable functions
/// have a documented, stable HTTPS contract - POST `{"data": …}` with a
/// `Authorization: Bearer <ID token>` header, reply `{"result": …}` or
/// `{"error": {…}}` - and that is all this needs. The emulator test suite
/// posts the identical shape, so both sides are exercised against one
/// contract.
///
/// ## What it deliberately does not send
///
/// No uid, no path, no collection name. The server reads the caller's
/// identity from the verified token only, and sending a uid would suggest
/// otherwise.
final class CallableAccountDeletionBackend: AccountDeletionBackend {

    /// How long to wait for the server before giving up on *this attempt*.
    ///
    /// Deletion is bounded on the server at 540s, but a user staring at a
    /// spinner is not. Past this the client reports that it could not
    /// confirm - not that deletion failed, because the job is very likely
    /// still running - and `deletionStatus()` is how it finds out.
    static let requestTimeout: TimeInterval = 90

    private let baseURL: URL
    private let session: URLSession
    private let idTokenProvider: () async throws -> String?
    private let logger = Logger(subsystem: "com.fridgefit.app", category: "AccountDeletion")

    init(
        baseURL: URL,
        session: URLSession = .shared,
        idTokenProvider: @escaping () async throws -> String? = {
            try await Auth.auth().currentUser?.getIDToken()
        }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.idTokenProvider = idTokenProvider
    }

    func requestDeletion() async throws -> RemoteDeletionOutcome {
        try await call(function: "requestAccountDeletion")
    }

    func deletionStatus() async throws -> RemoteDeletionOutcome {
        try await call(function: "accountDeletionStatus")
    }

    // MARK: - Transport

    private func call(function: String) async throws -> RemoteDeletionOutcome {
        guard let token = try await idTokenProvider(), !token.isEmpty else {
            throw DeleteAccountError.notSignedIn
        }

        var request = URLRequest(url: baseURL.appendingPathComponent(function))
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // The callable protocol requires a `data` envelope even when there is
        // nothing to send.
        request.httpBody = Data(#"{"data":{}}"#.utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            // Very likely still running server-side. Saying "failed" would be
            // a guess; the job is authoritative and can be polled.
            throw DeleteAccountError.deletionStatusUnknown(
                "the server didn't answer in time"
            )
        } catch {
            throw DeleteAccountError.backendUnreachable(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DeleteAccountError.backendUnreachable("no HTTP response")
        }

        return try Self.decode(status: http.statusCode, body: data, logger: logger)
    }

    // MARK: - Decoding

    /// Turns a callable reply into an outcome or a `DeleteAccountError`.
    ///
    /// Internal and static so every branch is testable from bytes, with no
    /// network and no Firebase.
    static func decode(
        status: Int,
        body: Data,
        logger: Logger = Logger(subsystem: "com.fridgefit.app", category: "AccountDeletion")
    ) throws -> RemoteDeletionOutcome {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]

        guard (200 ..< 300).contains(status) else {
            let error = json?["error"] as? [String: Any]
            let code = (error?["status"] as? String) ?? ""
            let message = (error?["message"] as? String) ?? "HTTP \(status)"
            logger.error("deletion endpoint refused: \(code, privacy: .public)")
            throw mapped(code: code, message: message, status: status)
        }

        guard let result = json?["result"] as? [String: Any] else {
            throw DeleteAccountError.deletionStatusUnknown("the server's reply could not be read")
        }

        // An unrecognised state is reported as unknown rather than guessed
        // at. Guessing `completed` would be the worst available error.
        let rawState = result["state"] as? String ?? ""
        guard let state = RemoteDeletionState(rawValue: rawState) else {
            throw DeleteAccountError.deletionStatusUnknown("unrecognised state \"\(rawState)\"")
        }

        return RemoteDeletionOutcome(
            state: state,
            // Taken from the server's own boolean, and cross-checked against
            // the state. The app must not report success on a disagreement.
            completed: (result["completed"] as? Bool ?? false) && state == .completed,
            deletedCollections: result["deletedCollections"] as? [String] ?? [],
            lastError: result["lastError"] as? String,
            attempts: result["attempts"] as? Int ?? 0
        )
    }

    /// Maps the callable error codes the backend actually returns.
    static func mapped(code: String, message: String, status: Int) -> DeleteAccountError {
        switch code {
        case "UNAUTHENTICATED":
            return .notSignedIn
        case "FAILED_PRECONDITION":
            // The server's recent-login requirement. Same user-visible
            // meaning as Firebase's own `requiresRecentLogin`, so it is
            // reported the same way and the sheet asks for the same proof.
            return .reauthenticationRequired([])
        case "PERMISSION_DENIED":
            return .accountDeletionFailed(message)
        default:
            if status == 404 {
                return .backendUnreachable("the deletion service is not deployed")
            }
            if (500 ..< 600).contains(status) {
                return .deletionStatusUnknown(message)
            }
            return .accountDeletionFailed(message)
        }
    }
}
