//
//  SignalingTransport.swift
//  FridgeFit
//

import Foundation

/// The signaling channel: how two peers exchange SDP and ICE before they
/// have a direct connection to exchange anything over.
///
/// Firestore is the real implementation. The protocol exists so
/// `WebRTCSessionCoordinator` - the part with the ordering rules that are
/// easy to get wrong - can be driven end to end by
/// `InMemorySignalingTransport` in unit tests, with no Firebase project and
/// no network.
nonisolated protocol SignalingTransport: AnyObject, Sendable {
    /// Writes a new session document. Fails if the ID is taken.
    func createSession(_ session: WebRTCSessionRecord) async throws

    func fetchSession(sessionId: String) async throws -> WebRTCSessionRecord?

    /// Writes the offer and moves the session to `.offering`.
    func setOffer(sessionId: String, offer: SessionDescriptionPayload) async throws

    /// Writes the answer and moves the session to `.answering`.
    func setAnswer(sessionId: String, answer: SessionDescriptionPayload) async throws

    /// Advances the session state.
    ///
    /// Implementations must refuse transitions `WebRTCSessionState`
    /// disallows, so a late write can't resurrect a closed session.
    func updateState(sessionId: String, state: WebRTCSessionState) async throws

    /// Appends one of our own ICE candidates to `role`'s subcollection.
    func appendCandidate(_ candidate: IceCandidatePayload, sessionId: String, from role: SignalingRole) async throws

    /// Watches the session document. Fires with the current value on attach.
    func observeSession(
        sessionId: String,
        onChange: @escaping @MainActor (WebRTCSessionRecord) -> Void,
        onRemoved: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) -> RemoteSubscription

    /// Watches the *other* side's candidate subcollection. Fires per added
    /// candidate, including ones written before the listener attached.
    func observeCandidates(
        sessionId: String,
        from role: SignalingRole,
        onCandidate: @escaping @MainActor (IceCandidatePayload) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) -> RemoteSubscription

    /// Watches for sessions addressed to this device as callee and not yet
    /// terminal. This is how a camera device learns someone wants to call it.
    func observeIncomingSessions(
        calleeDeviceId: String,
        onSession: @escaping @MainActor (WebRTCSessionRecord) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) -> RemoteSubscription

    /// Deletes the session and its candidate subcollections.
    func deleteSession(sessionId: String) async throws

    /// Deletes sessions whose `expiresAt` has passed.
    ///
    /// Run opportunistically when a device starts a session - a prototype
    /// with no backend has nowhere else to run a sweep, and leaving debris
    /// would eventually make `observeIncomingSessions` noisy.
    ///
    /// - Returns: how many were removed.
    @discardableResult
    func deleteExpiredSessions(now: Date) async throws -> Int
}
