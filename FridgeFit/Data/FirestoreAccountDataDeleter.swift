//
//  FirestoreAccountDataDeleter.swift
//  FridgeFit
//

import FirebaseAuth
import FirebaseFirestore
import Foundation
import OSLog

/// Deletes everything under `users/{uid}` in Firestore.
///
/// ## Why the collection list is written out
///
/// Firestore has no "delete this document and everything below it" operation
/// on the client, and `users/{uid}` is not even a real document in this app -
/// nothing ever writes fields to it, only to collections beneath it. So there
/// is no parent to delete and no recursion to ask for: the collections have
/// to be named. The list below is kept in step with `firestore.rules`, which
/// is the authoritative statement of what paths exist, and
/// `FirestoreAccountDataDeleterTests` asserts the two agree.
///
/// ## Subcollections do not cascade - this is the part that is easy to get wrong
///
/// Deleting a Firestore *document* does not delete its subcollections. The
/// document disappears from queries and its children carry on existing as
/// orphans at a path whose parent is gone. `webrtcSessions/{id}` has two of
/// them (`callerCandidates`, `calleeCandidates`), so each session's
/// candidates are listed and deleted *before* the session document itself.
/// Deleting the sessions first would strand every ICE candidate the user's
/// devices ever exchanged, with nothing left to enumerate them from.
///
/// ## What a client can and cannot guarantee
///
/// This runs entirely as the signed-in user, under the existing rules, with
/// no privilege escalation and no change to `firestore.rules`. That is a
/// deliberate limit, and it has one real consequence: a client-side
/// recursive delete is **best effort**. If the app is killed, loses the
/// network, or the user force-quits partway through, documents remain and the
/// next attempt finishes them off. What this cannot offer is atomicity, or
/// completion after the account has gone.
///
/// A guaranteed single-shot recursive delete needs the Admin SDK, which must
/// never ship inside an app - its credentials bypass all rules. The backend
/// contract that would provide it is specified in
/// `docs/assessment4-code-hardening-report.md`; it is not implemented here
/// because this repository contains no backend, and a stub that pretended to
/// call one would be worse than the honest client-side loop.
final class FirestoreAccountDataDeleter: AccountDataDeleting {

    /// Per-user collections whose documents own no subcollections, so
    /// deleting the documents is the whole job.
    static let flatCollections = [
        "pantry",
        "inventoryEvents",
        "savedRecipes",
        "devices",
        "fundsBudget",
        "fundsSpends",
        "fundsWaste",
        "fundsItemPrices",
        "fundsPriceBook",
    ]

    /// Handled separately, because its documents have children.
    static let sessionCollection = "webrtcSessions"

    /// The subcollections a session document owns. Matches
    /// `SignalingRole.candidateCollectionName`, and the rule in
    /// `firestore.rules` that restricts candidate writes to exactly these
    /// two names.
    static let candidateCollections = ["callerCandidates", "calleeCandidates"]

    /// Documents per batched commit. Firestore's hard limit is 500
    /// operations; staying under it leaves room and keeps one oversized
    /// pantry from failing the whole delete.
    private static let batchSize = 400

    private let firestore: Firestore
    private let logger = Logger(subsystem: "com.fridgefit.app", category: "AccountDeletion")

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func deleteAllData(ownedBy uid: String) async throws {
        guard !uid.isEmpty else {
            throw DeleteAccountError.remoteDataDeletionFailed("no account id")
        }

        let user = firestore.collection("users").document(uid)

        do {
            for name in Self.flatCollections {
                try await deleteAllDocuments(in: user.collection(name))
            }

            // Children first, then the parents, so nothing is orphaned.
            try await deleteSessions(in: user.collection(Self.sessionCollection))

            // The user document itself. Normally it holds no fields at all -
            // everything lives in the collections above - but deleting it is
            // what makes `users/{uid}` genuinely absent rather than an empty
            // shell, and deleting a document that does not exist is a no-op
            // in Firestore rather than an error.
            try await user.delete()
        } catch let error as DeleteAccountError {
            throw error
        } catch {
            logger.error("Remote deletion failed: \(error.localizedDescription, privacy: .public)")
            throw DeleteAccountError.remoteDataDeletionFailed(error.localizedDescription)
        }
    }

    /// Deletes every session's candidate subcollections, then the session
    /// documents themselves.
    private func deleteSessions(in collection: CollectionReference) async throws {
        let sessions = try await collection.getDocuments().documents

        for session in sessions {
            for candidates in Self.candidateCollections {
                try await deleteAllDocuments(in: session.reference.collection(candidates))
            }
        }

        try await deleteAllDocuments(in: collection)
    }

    /// Deletes every document in one collection, in batches.
    ///
    /// Re-reads the collection each round rather than paging through one
    /// snapshot: the set is shrinking as we go, and a fresh read is both
    /// simpler and correct if anything was added or removed in between. An
    /// empty collection exits on the first read, which is what makes a
    /// repeat run of a half-finished deletion cheap.
    private func deleteAllDocuments(in collection: CollectionReference) async throws {
        while true {
            try Task.checkCancellation()

            let snapshot = try await collection.limit(to: Self.batchSize).getDocuments()
            guard !snapshot.documents.isEmpty else { return }

            let batch = firestore.batch()
            for document in snapshot.documents {
                batch.deleteDocument(document.reference)
            }
            try await batch.commit()

            // A short page means that was the last one, so there is no need
            // to pay for a final empty read.
            if snapshot.documents.count < Self.batchSize { return }
        }
    }
}
