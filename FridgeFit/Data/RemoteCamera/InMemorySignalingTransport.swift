//
//  InMemorySignalingTransport.swift
//  FridgeFit
//

import Foundation

/// In-memory `SignalingTransport` standing in for one account's
/// `users/{uid}/webrtcSessions` collection.
///
/// One instance is one account's signaling space, so a test drives both ends
/// of a real negotiation by handing the same instance to two
/// `WebRTCSessionCoordinator`s. Callbacks are delivered with the same
/// `Task { @MainActor }` hop the Firestore implementation uses, so ordering
/// in tests matches ordering in the app.
nonisolated final class InMemorySignalingTransport: SignalingTransport, @unchecked Sendable {
    private struct SessionObserver {
        let sessionId: String
        let onChange: @MainActor (WebRTCSessionRecord) -> Void
        let onRemoved: @MainActor () -> Void
    }

    private struct CandidateObserver {
        let sessionId: String
        let role: SignalingRole
        let onCandidate: @MainActor (IceCandidatePayload) -> Void
    }

    private struct IncomingObserver {
        let calleeDeviceId: String
        let onSession: @MainActor (WebRTCSessionRecord) -> Void
    }

    nonisolated enum TransportError: Error, Equatable, Sendable {
        case sessionAlreadyExists(String)
        case sessionNotFound(String)
    }

    private let lock = NSLock()
    private var sessions: [String: WebRTCSessionRecord] = [:]
    private var candidates: [String: [SignalingRole: [IceCandidatePayload]]] = [:]
    private var sessionObservers: [UUID: SessionObserver] = [:]
    private var candidateObservers: [UUID: CandidateObserver] = [:]
    private var incomingObservers: [UUID: IncomingObserver] = [:]

    /// Set to make every call throw, for testing the rules-not-deployed path.
    var failureToThrow: Error?

    /// State transitions this transport refused, for asserting that the
    /// `WebRTCSessionState` table is actually being enforced.
    private(set) var rejectedTransitions: [(from: WebRTCSessionState, to: WebRTCSessionState)] = []

    init() {}

    // MARK: - Inspection helpers for tests

    var storedSessions: [WebRTCSessionRecord] {
        withLock { sessions.values.sorted { $0.sessionId < $1.sessionId } }
    }

    func storedCandidates(sessionId: String, from role: SignalingRole) -> [IceCandidatePayload] {
        withLock { candidates[sessionId]?[role] ?? [] }
    }

    var hasAnyStoredCandidates: Bool {
        withLock { candidates.values.contains { $0.values.contains { !$0.isEmpty } } }
    }

    // MARK: - SignalingTransport

    func createSession(_ session: WebRTCSessionRecord) async throws {
        try throwIfFailing()
        try withLock {
            guard sessions[session.sessionId] == nil else {
                throw TransportError.sessionAlreadyExists(session.sessionId)
            }
            sessions[session.sessionId] = session
        }
        notify(session: session)
        notifyIncoming(session: session)
    }

    func fetchSession(sessionId: String) async throws -> WebRTCSessionRecord? {
        try throwIfFailing()
        return withLock { sessions[sessionId] }
    }

    func setAnswer(sessionId: String, answer: SessionDescriptionPayload) async throws {
        try throwIfFailing()
        let updated = try mutateSession(sessionId) { session in
            session.with(offer: nil, answer: answer).with(state: .answering)
        }
        notify(session: updated)
    }

    func updateState(sessionId: String, state: WebRTCSessionState) async throws {
        try throwIfFailing()
        let updated: WebRTCSessionRecord? = withLock {
            guard let current = sessions[sessionId] else {
                // Matches the Firestore implementation: a state write against
                // a session that is already gone is the normal end of a
                // teardown race, not a failure.
                return nil
            }
            guard current.state.canTransition(to: state) else {
                rejectedTransitions.append((from: current.state, to: state))
                return nil
            }
            let next = current.with(state: state)
            sessions[sessionId] = next
            return next
        }
        guard let updated else { return }
        notify(session: updated)
    }

    func appendCandidate(
        _ candidate: IceCandidatePayload,
        sessionId: String,
        from role: SignalingRole
    ) async throws {
        try throwIfFailing()
        let listeners = withLock { () -> [CandidateObserver] in
            var byRole = candidates[sessionId] ?? [:]
            byRole[role, default: []].append(candidate)
            candidates[sessionId] = byRole
            return candidateObservers.values.filter { $0.sessionId == sessionId && $0.role == role }
        }
        for listener in listeners {
            let deliver = listener.onCandidate
            Task { @MainActor in deliver(candidate) }
        }
    }

    func observeSession(
        sessionId: String,
        onChange: @escaping @MainActor (WebRTCSessionRecord) -> Void,
        onRemoved: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) -> RemoteSubscription {
        if let failureToThrow {
            Task { @MainActor in onError(failureToThrow) }
            return ClosureSubscription {}
        }
        let token = UUID()
        let existing = withLock { () -> WebRTCSessionRecord? in
            sessionObservers[token] = SessionObserver(sessionId: sessionId, onChange: onChange, onRemoved: onRemoved)
            return sessions[sessionId]
        }

        if let existing {
            Task { @MainActor in onChange(existing) }
        }
        return ClosureSubscription { [weak self] in
            self?.withLock { self?.sessionObservers[token] = nil }
        }
    }

    func observeCandidates(
        sessionId: String,
        from role: SignalingRole,
        onCandidate: @escaping @MainActor (IceCandidatePayload) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) -> RemoteSubscription {
        if let failureToThrow {
            Task { @MainActor in onError(failureToThrow) }
            return ClosureSubscription {}
        }
        let token = UUID()
        let backlog = withLock { () -> [IceCandidatePayload] in
            candidateObservers[token] = CandidateObserver(sessionId: sessionId, role: role, onCandidate: onCandidate)
            return candidates[sessionId]?[role] ?? []
        }

        // Replay what the peer already wrote, like a Firestore listener's
        // initial snapshot reporting existing documents as `.added`.
        for candidate in backlog {
            Task { @MainActor in onCandidate(candidate) }
        }
        return ClosureSubscription { [weak self] in
            self?.withLock { self?.candidateObservers[token] = nil }
        }
    }

    func observeIncomingSessions(
        calleeDeviceId: String,
        onSession: @escaping @MainActor (WebRTCSessionRecord) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) -> RemoteSubscription {
        if let failureToThrow {
            Task { @MainActor in onError(failureToThrow) }
            return ClosureSubscription {}
        }
        let token = UUID()
        let backlog = withLock { () -> [WebRTCSessionRecord] in
            incomingObservers[token] = IncomingObserver(calleeDeviceId: calleeDeviceId, onSession: onSession)
            return sessions.values.filter { $0.calleeDeviceId == calleeDeviceId }
        }

        for session in backlog.sorted(by: { $0.sessionId < $1.sessionId }) {
            Task { @MainActor in onSession(session) }
        }
        return ClosureSubscription { [weak self] in
            self?.withLock { self?.incomingObservers[token] = nil }
        }
    }

    func deleteSession(sessionId: String) async throws {
        try throwIfFailing()
        let listeners = withLock { () -> [SessionObserver] in
            sessions[sessionId] = nil
            candidates[sessionId] = nil
            return sessionObservers.values.filter { $0.sessionId == sessionId }
        }
        for listener in listeners {
            let deliver = listener.onRemoved
            Task { @MainActor in deliver() }
        }
    }

    @discardableResult
    func deleteExpiredSessions(now: Date) async throws -> Int {
        try throwIfFailing()
        let expired = withLock { sessions.values.filter { $0.isExpired(now: now) }.map(\.sessionId) }
        for sessionId in expired {
            try await deleteSession(sessionId: sessionId)
        }
        return expired.count
    }

    // MARK: - Internals

    /// Scoped locking. `NSLock.lock()` is unavailable from async contexts, so
    /// every critical section here - none of which contains an await - goes
    /// through this synchronous helper.
    private func withLock<T>(_ work: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try work()
    }

    private func throwIfFailing() throws {
        if let failureToThrow { throw failureToThrow }
    }

    private func mutateSession(
        _ sessionId: String,
        _ work: (WebRTCSessionRecord) -> WebRTCSessionRecord
    ) throws -> WebRTCSessionRecord {
        try withLock {
            guard let current = sessions[sessionId] else {
                throw TransportError.sessionNotFound(sessionId)
            }
            let updated = work(current)
            sessions[sessionId] = updated
            return updated
        }
    }

    private func notify(session: WebRTCSessionRecord) {
        let listeners = withLock { sessionObservers.values.filter { $0.sessionId == session.sessionId } }
        for listener in listeners {
            let deliver = listener.onChange
            Task { @MainActor in deliver(session) }
        }
    }

    private func notifyIncoming(session: WebRTCSessionRecord) {
        let listeners = withLock { incomingObservers.values.filter { $0.calleeDeviceId == session.calleeDeviceId } }
        for listener in listeners {
            let deliver = listener.onSession
            Task { @MainActor in deliver(session) }
        }
    }
}
