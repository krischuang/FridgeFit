//
//  FirestoreSignalingTransport.swift
//  FridgeFit
//

import FirebaseAuth
@preconcurrency import FirebaseFirestore
import Foundation

/// Firestore-backed signaling, at `users/{uid}/webrtcSessions/{sessionId}`
/// with ICE candidates in `callerCandidates` / `calleeCandidates`
/// subcollections.
///
/// Only SDP and ICE go through here. Video frames and captured photos travel
/// peer-to-peer over WebRTC - putting media in Firestore would be both
/// ruinously slow and a permanent copy of something the user didn't ask to
/// store.
///
/// Every call is wrapped by `FirestoreDiagnostics`, so a denial names the
/// operation and the path. That matters most for the candidate
/// subcollections: a rule on the session document does **not** cascade to
/// them, and the resulting failure - SDP exchanged, connection never
/// completes - looks like a networking fault unless the error says otherwise.
nonisolated final class FirestoreSignalingTransport: SignalingTransport {
    private let firestore: Firestore
    private let userIDProvider: @Sendable () -> String?

    init(
        firestore: Firestore = Firestore.firestore(),
        userIDProvider: @escaping @Sendable () -> String? = { Auth.auth().currentUser?.uid }
    ) {
        self.firestore = firestore
        self.userIDProvider = userIDProvider
    }

    private func sessionsCollection() throws -> CollectionReference {
        guard let uid = userIDProvider(), !uid.isEmpty else {
            throw RemoteCameraError.notAuthenticated
        }
        return firestore.collection("users").document(uid).collection("webrtcSessions")
    }

    private func sessionDocument(_ sessionId: String) throws -> DocumentReference {
        try sessionsCollection().document(sessionId)
    }

    // Diagnostic paths, with `{uid}` already in place.
    private var sessionsPath: String { "users/{uid}/webrtcSessions" }
    private func sessionPath(_ sessionId: String) -> String { "\(sessionsPath)/\(sessionId)" }
    private func candidatesPath(_ sessionId: String, _ role: SignalingRole) -> String {
        "\(sessionPath(sessionId))/\(role.candidateCollectionName)"
    }

    // MARK: - Session lifecycle

    func createSession(_ session: WebRTCSessionRecord) async throws {
        let uid = userIDProvider()
        let document = try sessionDocument(session.sessionId)
        try await FirestoreDiagnostics.perform(
            .create, path: sessionPath(session.sessionId), uid: uid
        ) {
            try await document.setData(session.encodedForCreate)
        }
    }

    func fetchSession(sessionId: String) async throws -> WebRTCSessionRecord? {
        let uid = userIDProvider()
        let document = try sessionDocument(sessionId)
        let snapshot = try await FirestoreDiagnostics.perform(
            .read, path: sessionPath(sessionId), uid: uid
        ) {
            try await document.getDocument()
        }
        guard let data = snapshot.data() else { return nil }
        return WebRTCSessionRecord.decode(
            id: snapshot.documentID,
            data: FirestoreDeviceRegistry.withResolvedDates(data)
        )
    }

    func setOffer(sessionId: String, offer: SessionDescriptionPayload) async throws {
        let uid = userIDProvider()
        let document = try sessionDocument(sessionId)
        try await FirestoreDiagnostics.perform(.update, path: sessionPath(sessionId), uid: uid) {
            try await document.updateData([
                WebRTCSessionRecord.Field.offer: offer.encoded,
                WebRTCSessionRecord.Field.state: WebRTCSessionState.offering.rawValue,
            ])
        }
    }

    func setAnswer(sessionId: String, answer: SessionDescriptionPayload) async throws {
        let uid = userIDProvider()
        let document = try sessionDocument(sessionId)
        try await FirestoreDiagnostics.perform(.update, path: sessionPath(sessionId), uid: uid) {
            try await document.updateData([
                WebRTCSessionRecord.Field.answer: answer.encoded,
                WebRTCSessionRecord.Field.state: WebRTCSessionState.answering.rawValue,
            ])
        }
    }

    /// Advances the state, refusing moves `WebRTCSessionState` disallows.
    ///
    /// Done in a transaction because both peers write this field: without
    /// one, the camera's `connected` write and the controller's could
    /// interleave such that a `closed` session gets reopened. The guard lives
    /// here rather than in Firestore rules because rules can't express
    /// "previous value was X" without `resource.data`, and keeping the
    /// transition table in one Swift type keeps it testable.
    func updateState(sessionId: String, state: WebRTCSessionState) async throws {
        let uid = userIDProvider()
        let document = try sessionDocument(sessionId)
        try await FirestoreDiagnostics.perform(.update, path: sessionPath(sessionId), uid: uid) {
            _ = try await self.firestore.runTransaction { transaction, errorPointer in
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(document)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }
                guard
                    let data = snapshot.data(),
                    let rawCurrent = data[WebRTCSessionRecord.Field.state] as? String,
                    let current = WebRTCSessionState(rawValue: rawCurrent)
                else {
                    // Document gone or unreadable. Not an error worth
                    // surfacing - the session being over is the normal cause.
                    return nil
                }
                guard current.canTransition(to: state) else { return nil }
                transaction.updateData(
                    [WebRTCSessionRecord.Field.state: state.rawValue],
                    forDocument: document
                )
                return nil
            }
        }
    }

    func appendCandidate(
        _ candidate: IceCandidatePayload,
        sessionId: String,
        from role: SignalingRole
    ) async throws {
        let uid = userIDProvider()
        let collection = try sessionDocument(sessionId).collection(role.candidateCollectionName)
        try await FirestoreDiagnostics.perform(
            .create, path: candidatesPath(sessionId, role), uid: uid
        ) {
            _ = try await collection.addDocument(data: candidate.encoded)
        }
    }

    // MARK: - Observation

    func observeSession(
        sessionId: String,
        onChange: @escaping @MainActor (WebRTCSessionRecord) -> Void,
        onRemoved: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) -> RemoteSubscription {
        // The provider, not a snapshotted value: re-read on failure so a
        // sign-out is reported as such.
        let currentUID = userIDProvider
        let document: DocumentReference
        do {
            document = try sessionDocument(sessionId)
        } catch {
            Task { @MainActor in onError(error) }
            return ClosureSubscription {}
        }

        let path = sessionPath(sessionId)
        let registration = document.addSnapshotListener { snapshot, error in
            if let error {
                // Re-read auth here rather than using the uid captured
                // when the listener attached: if the user signed out in the
                // meantime, that is the real cause and it should be reported
                // as `notAuthenticated`, not as a rules problem.
                let reported = FirestoreDiagnostics.report(
                    error, operation: .listen, path: path, uid: currentUID()
                )
                Task { @MainActor in onError(reported) }
                return
            }
            guard let snapshot else { return }
            guard let data = snapshot.data(), snapshot.exists else {
                Task { @MainActor in onRemoved() }
                return
            }
            guard let record = WebRTCSessionRecord.decode(
                id: snapshot.documentID,
                data: FirestoreDeviceRegistry.withResolvedDates(data)
            ) else {
                return
            }
            Task { @MainActor in onChange(record) }
        }
        return ClosureSubscription { registration.remove() }
    }

    func observeCandidates(
        sessionId: String,
        from role: SignalingRole,
        onCandidate: @escaping @MainActor (IceCandidatePayload) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) -> RemoteSubscription {
        // The provider, not a snapshotted value: re-read on failure so a
        // sign-out is reported as such.
        let currentUID = userIDProvider
        let collection: CollectionReference
        do {
            collection = try sessionDocument(sessionId).collection(role.candidateCollectionName)
        } catch {
            Task { @MainActor in onError(error) }
            return ClosureSubscription {}
        }

        let path = candidatesPath(sessionId, role)
        let registration = collection.addSnapshotListener { snapshot, error in
            if let error {
                // Re-read auth here rather than using the uid captured
                // when the listener attached: if the user signed out in the
                // meantime, that is the real cause and it should be reported
                // as `notAuthenticated`, not as a rules problem.
                let reported = FirestoreDiagnostics.report(
                    error, operation: .listen, path: path, uid: currentUID()
                )
                Task { @MainActor in onError(reported) }
                return
            }
            guard let snapshot else { return }
            // `.added` only. The initial snapshot reports every existing
            // document as added, which is what picks up candidates the peer
            // wrote before this listener attached.
            for change in snapshot.documentChanges where change.type == .added {
                guard let payload = IceCandidatePayload.decode(change.document.data()) else { continue }
                Task { @MainActor in onCandidate(payload) }
            }
        }
        return ClosureSubscription { registration.remove() }
    }

    func observeIncomingSessions(
        calleeDeviceId: String,
        onSession: @escaping @MainActor (WebRTCSessionRecord) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) -> RemoteSubscription {
        // The provider, not a snapshotted value: re-read on failure so a
        // sign-out is reported as such.
        let currentUID = userIDProvider
        let query: Query
        do {
            // Single-field equality filter, so this needs no composite index.
            // Terminal and expired sessions are filtered in Swift instead of
            // with a second `where` clause for exactly that reason.
            query = try sessionsCollection()
                .whereField(WebRTCSessionRecord.Field.calleeDeviceId, isEqualTo: calleeDeviceId)
        } catch {
            Task { @MainActor in onError(error) }
            return ClosureSubscription {}
        }

        let path = sessionsPath
        let registration = query.addSnapshotListener { snapshot, error in
            if let error {
                // Re-read auth here rather than using the uid captured
                // when the listener attached: if the user signed out in the
                // meantime, that is the real cause and it should be reported
                // as `notAuthenticated`, not as a rules problem.
                let reported = FirestoreDiagnostics.report(
                    error, operation: .listen, path: path, uid: currentUID()
                )
                Task { @MainActor in onError(reported) }
                return
            }
            guard let snapshot else { return }
            for document in snapshot.documents {
                guard let record = WebRTCSessionRecord.decode(
                    id: document.documentID,
                    data: FirestoreDeviceRegistry.withResolvedDates(document.data())
                ) else { continue }
                Task { @MainActor in onSession(record) }
            }
        }
        return ClosureSubscription { registration.remove() }
    }

    // MARK: - Cleanup

    /// Deletes the session and both candidate subcollections.
    ///
    /// Subcollections are not removed by deleting the parent in Firestore, so
    /// skipping this would leave orphaned candidate documents that nothing
    /// will ever read or clean up.
    func deleteSession(sessionId: String) async throws {
        let uid = userIDProvider()
        let document = try sessionDocument(sessionId)

        for role in [SignalingRole.caller, .callee] {
            let collection = document.collection(role.candidateCollectionName)
            let candidates = try await FirestoreDiagnostics.perform(
                .list, path: candidatesPath(sessionId, role), uid: uid
            ) {
                try await collection.getDocuments()
            }
            for candidate in candidates.documents {
                try await FirestoreDiagnostics.perform(
                    .delete, path: candidatesPath(sessionId, role), uid: uid
                ) {
                    try await candidate.reference.delete()
                }
            }
        }

        try await FirestoreDiagnostics.perform(.delete, path: sessionPath(sessionId), uid: uid) {
            try await document.delete()
        }
    }

    @discardableResult
    func deleteExpiredSessions(now: Date) async throws -> Int {
        let uid = userIDProvider()
        let collection = try sessionsCollection()
        let snapshot = try await FirestoreDiagnostics.perform(.list, path: sessionsPath, uid: uid) {
            try await collection
                .whereField(WebRTCSessionRecord.Field.expiresAt, isLessThan: Timestamp(date: now))
                .getDocuments()
        }
        for document in snapshot.documents {
            try await deleteSession(sessionId: document.documentID)
        }
        return snapshot.documents.count
    }
}
