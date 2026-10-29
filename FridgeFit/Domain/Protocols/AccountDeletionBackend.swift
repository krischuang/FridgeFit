//
//  AccountDeletionBackend.swift
//  FridgeFit
//

import Foundation

/// How far a server-side deletion job has got.
///
/// Mirrors the `DeletionState` union in `functions/src/deletion.ts`. The two
/// are kept in step by `AccountDeletionBackendTests`, which parses the
/// TypeScript source - a state the server can report and the client cannot
/// decode would otherwise surface as a generic failure for a deletion that
/// is actually progressing.
nonisolated enum RemoteDeletionState: String, Equatable, Sendable, CaseIterable {
    /// Accepted, not started. Also what the server reports for a user who
    /// has never requested deletion.
    case pending
    /// Firestore data is being removed. Nothing irreversible yet.
    case deletingData
    /// All Firestore data is gone. The login still exists.
    case dataDeleted
    /// The login is being removed.
    case deletingAuth
    /// Finished: data and account are both gone.
    case completed
    /// Stopped. Retryable - every stage on the server is idempotent.
    case failed

    /// Whether the user's data has already gone at this point. Drives the
    /// warning that stopping now leaves a working login over an empty
    /// account.
    var dataAlreadyDeleted: Bool {
        switch self {
        case .dataDeleted, .deletingAuth, .completed:
            return true
        case .pending, .deletingData, .failed:
            return false
        }
    }

    /// Whether the job is still moving. A client that sees one of these
    /// should poll rather than report a failure.
    var isInProgress: Bool {
        switch self {
        case .deletingData, .deletingAuth:
            return true
        case .pending, .dataDeleted, .completed, .failed:
            return false
        }
    }
}

/// What the server said about a deletion job.
nonisolated struct RemoteDeletionOutcome: Equatable, Sendable {
    let state: RemoteDeletionState
    /// True **only** when the backend confirms the account and all of its
    /// data are gone. The app never reports success on anything else.
    let completed: Bool
    let deletedCollections: [String]
    let lastError: String?
    let attempts: Int

    init(
        state: RemoteDeletionState,
        completed: Bool,
        deletedCollections: [String] = [],
        lastError: String? = nil,
        attempts: Int = 0
    ) {
        self.state = state
        self.completed = completed
        self.deletedCollections = deletedCollections
        self.lastError = lastError
        self.attempts = attempts
    }
}

/// The server-side deletion endpoint.
///
/// Abstracted so `DeleteAccountUseCase` can be driven without a network, and
/// so the app can run with no backend at all - which is the shipping
/// configuration today. See `AccountDeletionBackendConfiguration`.
protocol AccountDeletionBackend: AnyObject {
    /// Starts or resumes deletion of the signed-in user's account, and waits
    /// for the server's verdict.
    ///
    /// Deliberately takes **no uid**. The server derives it from the verified
    /// ID token; a uid parameter here would imply the server trusts one, and
    /// the whole security property of the endpoint is that it does not.
    func requestDeletion() async throws -> RemoteDeletionOutcome

    /// Re-reads the job, for a client that lost the connection mid-deletion
    /// or is resuming after a relaunch.
    func deletionStatus() async throws -> RemoteDeletionOutcome
}
