//
//  WebRTCSessionCoordinator.swift
//  FridgeFit
//

import Foundation
import OSLog

/// Drives one remote-camera session from either end: creates or accepts the
/// signaling document, runs offer/answer in the right order, pumps ICE
/// candidates both ways, and tears everything down exactly once.
///
/// This is where the ordering rules that are easy to get wrong live, so it
/// depends only on `SignalingTransport` and `PeerConnectionControlling` -
/// both of which have test doubles. `WebRTCSessionCoordinatorTests` drives
/// two of these against one `InMemorySignalingTransport` and gets a complete
/// negotiation with no Firebase, no camera and no network.
///
/// ## Who calls whom
///
/// The controller is always the caller and the camera always the callee.
/// Fixing that up front is what avoids SDP glare - neither side has to
/// detect a simultaneous offer and back off, because only one side ever
/// creates one.
@MainActor
final class WebRTCSessionCoordinator {
    nonisolated enum Event: Sendable {
        case statusChanged(DeviceConnectionStatus)
        /// The other end is known - used to label "Connected to <name>".
        case peerIdentified(deviceId: String, deviceName: String)
        case controlMessage(RemoteControlMessage)
        case binaryFrame(Data)
        /// Real video frames confirmed arriving. Only the controller sees this.
        case videoConfirmed
        case failed(RemoteCameraError)
        /// The session is over and everything has been cleaned up.
        case ended(reason: String)
    }

    /// How long after ICE connects the controller waits for a first decoded
    /// frame before calling it a failure.
    ///
    /// On a LAN the first frame lands well under a second. Eight seconds is
    /// generous enough to survive a slow H.264 keyframe, and short enough
    /// that a user staring at a black rectangle gets told why.
    /// `nonisolated` so it can be read from the default argument below,
    /// which is evaluated outside the main actor.
    nonisolated static let mediaGracePeriod: Duration = .seconds(8)

    private let identity: DeviceIdentity
    private let role: SignalingRole
    private let transport: any SignalingTransport
    private let makePeerConnection: @MainActor () -> any PeerConnectionControlling
    private let now: () -> Date
    /// Injectable so the "connected but no video" path can be tested without
    /// a test sitting idle for `Self.mediaGracePeriod`.
    private let mediaGracePeriod: Duration
    private let logger = Logger(subsystem: "com.Fridge.FridgeFit", category: "WebRTC")

    private var onEvent: ((Event) -> Void)?

    private var peer: (any PeerConnectionControlling)?
    private var sessionId: String?
    private var peerDeviceId: String?
    private var sessionSubscription: RemoteSubscription?
    private var candidateSubscription: RemoteSubscription?
    private var incomingSubscription: RemoteSubscription?
    private var mediaWatchdog: Task<Void, Never>?

    /// Candidates the peer published before we had a remote description.
    ///
    /// `addIceCandidate` is only legal after `setRemoteDescription`, and the
    /// callee reliably receives candidates before it has finished answering.
    /// Dropping them instead of buffering them is a classic cause of
    /// "sometimes connects" flakiness.
    private var queuedRemoteCandidates: [IceCandidatePayload] = []
    /// Our own candidates, held until the session document exists.
    ///
    /// Pre-gathering plus building the offer before the Firestore write means
    /// ICE can start producing candidates while that write is still in
    /// flight. Publishing them into a subcollection whose parent document
    /// does not exist yet would work in Firestore and would be unreadable
    /// debris if the write then failed, so they wait here instead. Nothing is
    /// lost by waiting: the peer cannot use a candidate until it has seen the
    /// session and applied the offer, which cannot happen before that write
    /// lands.
    private var pendingLocalCandidates: [IceCandidatePayload] = []
    private var isSessionPublished = false
    private var hasRemoteDescription = false
    private var hasConfirmedVideo = false
    /// Guards `disconnect` so a peer `session_end`, an ICE failure and a user
    /// tap racing each other produce one teardown and one `.ended`.
    private var isTearingDown = false

    private(set) var status: DeviceConnectionStatus = .available

    init(
        identity: DeviceIdentity,
        role: SignalingRole,
        transport: any SignalingTransport,
        makePeerConnection: @escaping @MainActor () -> any PeerConnectionControlling,
        now: @escaping () -> Date = { Date() },
        mediaGracePeriod: Duration = WebRTCSessionCoordinator.mediaGracePeriod
    ) {
        self.identity = identity
        self.role = role
        self.transport = transport
        self.makePeerConnection = makePeerConnection
        self.now = now
        self.mediaGracePeriod = mediaGracePeriod
    }

    /// Releases listeners and timers without the main-actor hop an isolated
    /// deinit needs.
    ///
    /// Same reason as `DeviceHeartbeat`: a `@MainActor` class gets an
    /// isolated `deinit`, and performing one inside another - as happens when
    /// a view model owning this coordinator is torn down - corrupts the
    /// concurrency runtime's task-local stack and aborts the process. None of
    /// this cleanup needs the main actor; cancelling tasks and snapshot
    /// listeners is safe from any thread.
    ///
    /// This is a backstop, not the main path. A session that ends properly
    /// goes through `disconnect`, which also closes the signaling document.
    nonisolated deinit {
        mediaWatchdog?.cancel()
        sessionSubscription?.cancel()
        candidateSubscription?.cancel()
        incomingSubscription?.cancel()
    }

    func setEventHandler(_ handler: @escaping (Event) -> Void) {
        onEvent = handler
    }

    var activeSessionId: String? { sessionId }
    var connectedPeerDeviceId: String? { peerDeviceId }

    // MARK: - Camera side (callee)

    /// Starts watching for offers addressed to this device.
    ///
    /// Only meaningful for `.callee`. Sessions aimed at another device, or
    /// ones this device somehow created itself, are ignored - that second
    /// check is what prevents a device connecting to itself if it is
    /// registered in both roles.
    func startListeningForIncomingSessions() {
        guard role == .callee else {
            assertionFailure("Only the callee listens for incoming sessions")
            return
        }
        // Debris from a crashed or backgrounded run is cleared here rather
        // than when someone starts a session. The sweep is a query plus a
        // delete per leftover session, and it used to be awaited in the
        // middle of `connect`, where every one of those round trips sat
        // directly between the user's tap and the offer being written. Camera
        // Mode is opened well before anyone calls, so the same work costs
        // nothing here, and both devices share one sessions collection so
        // either side sweeping is enough.
        sweepExpiredSessions()

        incomingSubscription?.cancel()
        incomingSubscription = transport.observeIncomingSessions(
            calleeDeviceId: identity.deviceId,
            onSession: { [weak self] session in
                self?.handleIncoming(session: session)
            },
            onError: { [weak self] error in
                self?.report(underlying: error)
            }
        )
    }

    private func handleIncoming(session: WebRTCSessionRecord) {
        guard sessionId == nil else {
            // Already busy. Leaving the second session alone lets it expire
            // rather than silently dropping the live one.
            if session.sessionId != sessionId {
                logger.info("Ignoring session \(session.sessionId, privacy: .public) - already in a session")
            }
            return
        }
        guard session.calleeDeviceId == identity.deviceId else {
            report(.sessionNotAddressedToThisDevice)
            return
        }
        guard session.callerDeviceId != identity.deviceId else {
            logger.error("Refusing self-connection for device \(self.identity.logTag, privacy: .public)")
            return
        }
        guard !session.isExpired(now: now()) else {
            Task { try? await self.transport.deleteSession(sessionId: session.sessionId) }
            return
        }
        guard session.state == .offering, let offer = session.offer else {
            return
        }

        Task { await self.accept(session: session, offer: offer) }
    }

    private func accept(session: WebRTCSessionRecord, offer: SessionDescriptionPayload) async {
        sessionId = session.sessionId
        // The caller already wrote the document this side is answering, so
        // candidates may be published the moment they are gathered.
        isSessionPublished = true
        peerDeviceId = session.callerDeviceId
        emit(.peerIdentified(deviceId: session.callerDeviceId, deviceName: session.callerDeviceName))
        update(status: .connecting)

        do {
            let connection = try startPeerConnection()
            // Remote description first: the callee can only build an answer
            // once it knows what was offered, and the answer's media
            // directions are derived from the offer's.
            try await connection.setRemoteDescription(offer)
            hasRemoteDescription = true
            try await drainQueuedCandidates(into: connection)

            observeSessionDocument()
            observePeerCandidates()

            let answer = try await connection.createAnswer()
            try await transport.setAnswer(sessionId: session.sessionId, answer: answer)
            logger.info("Answered session \(session.sessionId, privacy: .public)")
        } catch {
            await failSession(with: error)
        }
    }

    // MARK: - Controller side (caller)

    /// Creates a session aimed at `cameraDeviceId` and offers.
    func connect(toCameraDeviceId cameraDeviceId: String, cameraDeviceName: String) async {
        guard role == .caller else {
            assertionFailure("Only the caller initiates sessions")
            return
        }
        guard sessionId == nil else { return }
        guard cameraDeviceId != identity.deviceId else {
            // Same install can be registered as camera and controller; it
            // must not be able to pick itself out of its own device list.
            report(.sessionNotAddressedToThisDevice)
            return
        }

        let newSessionId = UUID().uuidString
        sessionId = newSessionId
        peerDeviceId = cameraDeviceId
        emit(.peerIdentified(deviceId: cameraDeviceId, deviceName: cameraDeviceName))
        update(status: .connecting)

        do {
            // Everything local happens before anything is written. Building
            // the peer connection and the offer costs no network, and
            // `createOffer` is what starts ICE gathering - so by the time the
            // single write below is acknowledged, candidates are usually
            // already waiting in `pendingLocalCandidates`.
            let connection = try startPeerConnection()

            // Candidates only. `observeSessionDocument` has to wait until the
            // document exists: a Firestore document listener reports a
            // missing document as a snapshot with `exists == false`, which
            // this coordinator reads as the peer having cleaned up and
            // answers by tearing the session down. The candidate listener has
            // no such problem - an absent subcollection is simply empty.
            observePeerCandidates()

            let offer = try await connection.createOffer()

            // One write, not two. The session used to be created empty at
            // `.creating` and then updated with the offer, which cost a
            // second acknowledged round trip and made the camera wake up for
            // a snapshot it could only discard - `handleIncoming` ignores any
            // state that is not `.offering`. Writing the offer with the
            // document removes both.
            let createdAt = now()
            let record = WebRTCSessionRecord(
                sessionId: newSessionId,
                callerDeviceId: identity.deviceId,
                callerDeviceName: identity.deviceName,
                calleeDeviceId: cameraDeviceId,
                calleeDeviceName: cameraDeviceName,
                state: .offering,
                offer: offer,
                answer: nil,
                createdAt: createdAt,
                expiresAt: createdAt.addingTimeInterval(WebRTCSessionRecord.timeToLive)
            )
            try await transport.createSession(record)
            observeSessionDocument()
            publishPendingLocalCandidates()
            logger.info("Offered session \(newSessionId, privacy: .public)")
        } catch {
            await failSession(with: error)
        }
    }

    /// Clears expired signaling sessions without holding anything up.
    ///
    /// Deliberately not awaited by any caller: it is best effort, its result
    /// is only logged, and nothing in a negotiation depends on it.
    private func sweepExpiredSessions() {
        Task { [transport, now, logger] in
            do {
                let removed = try await transport.deleteExpiredSessions(now: now())
                if removed > 0 { logger.info("Swept \(removed) expired signaling session(s)") }
            } catch {
                logger.info("Expired-session sweep skipped: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Shared negotiation

    private func startPeerConnection() throws -> any PeerConnectionControlling {
        let connection = makePeerConnection()
        connection.events = { [weak self] event in
            self?.handle(peerEvent: event)
        }
        try connection.start(role: role)
        peer = connection
        return connection
    }

    private func observeSessionDocument() {
        guard let sessionId else { return }
        sessionSubscription?.cancel()
        sessionSubscription = transport.observeSession(
            sessionId: sessionId,
            onChange: { [weak self] record in
                self?.handle(sessionChange: record)
            },
            onRemoved: { [weak self] in
                // The other side cleaned up. Nothing left to close remotely.
                self?.finishTeardown(reason: "the session ended")
            },
            onError: { [weak self] error in
                self?.report(underlying: error)
            }
        )
    }

    private func observePeerCandidates() {
        guard let sessionId else { return }
        candidateSubscription?.cancel()
        candidateSubscription = transport.observeCandidates(
            sessionId: sessionId,
            from: role.other,
            onCandidate: { [weak self] candidate in
                self?.handle(remoteCandidate: candidate)
            },
            onError: { [weak self] error in
                self?.report(underlying: error)
            }
        )
    }

    private func handle(sessionChange record: WebRTCSessionRecord) {
        guard record.sessionId == sessionId else { return }
        guard record.role(for: identity.deviceId) != nil else {
            report(.sessionNotAddressedToThisDevice)
            return
        }

        switch record.state {
        case .closed:
            finishTeardown(reason: "\(record.peerDeviceName(from: role)) ended the session")
        case .failed:
            update(status: .failed)
        case .answering where role == .caller:
            // Our offer was answered. Apply it once - a repeat snapshot of
            // the same document must not re-enter negotiation.
            guard !hasRemoteDescription, let answer = record.answer else { return }
            Task { await self.applyRemoteAnswer(answer) }
        case .creating, .offering, .answering, .connected:
            break
        }
    }

    private func applyRemoteAnswer(_ answer: SessionDescriptionPayload) async {
        guard let connection = peer, !hasRemoteDescription else { return }
        do {
            try await connection.setRemoteDescription(answer)
            hasRemoteDescription = true
            try await drainQueuedCandidates(into: connection)
        } catch {
            await failSession(with: error)
        }
    }

    private func handle(remoteCandidate candidate: IceCandidatePayload) {
        guard let connection = peer else { return }
        guard hasRemoteDescription else {
            queuedRemoteCandidates.append(candidate)
            return
        }
        Task {
            do {
                try await connection.addRemoteCandidate(candidate)
            } catch {
                // A single rejected candidate is survivable - others may
                // still produce a working pair - so this is logged, not
                // escalated to a session failure.
                self.logger.info("Dropped a remote ICE candidate: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Flushes everything ICE produced while the session document was still
    /// being written, and lets later candidates go straight out.
    private func publishPendingLocalCandidates() {
        isSessionPublished = true
        let pending = pendingLocalCandidates
        pendingLocalCandidates.removeAll()
        for candidate in pending {
            publish(localCandidate: candidate)
        }
    }

    private func publish(localCandidate candidate: IceCandidatePayload) {
        guard let sessionId else { return }
        Task {
            do {
                try await self.transport.appendCandidate(candidate, sessionId: sessionId, from: self.role)
            } catch {
                self.logger.info("Could not publish a local ICE candidate: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func drainQueuedCandidates(into connection: any PeerConnectionControlling) async throws {
        let queued = queuedRemoteCandidates
        queuedRemoteCandidates.removeAll()
        for candidate in queued {
            try await connection.addRemoteCandidate(candidate)
        }
    }

    private func handle(peerEvent event: PeerConnectionEvent) {
        switch event {
        case .localCandidate(let candidate):
            guard sessionId != nil else { return }
            guard isSessionPublished else {
                pendingLocalCandidates.append(candidate)
                return
            }
            publish(localCandidate: candidate)

        case .connectionState(let state):
            handle(connectionState: state)

        case .dataChannelOpen:
            logger.info("Data channel open for session \(self.sessionId ?? "-", privacy: .public)")

        case .dataChannelClosed:
            logger.info("Data channel closed for session \(self.sessionId ?? "-", privacy: .public)")

        case .controlMessage(let message):
            if case .sessionEnd(let reason) = message {
                finishTeardown(reason: reason)
                return
            }
            emit(.controlMessage(message))

        case .malformedControlMessage(let reason):
            // Logged and dropped. A peer on a different build must not be
            // able to break this one with a frame it doesn't understand.
            logger.info("Ignored a malformed control frame: \(reason, privacy: .public)")

        case .binaryFrame(let data):
            emit(.binaryFrame(data))

        case .remoteVideoTrackAdded:
            logger.info("Remote video track negotiated")

        case .firstRemoteFrameRendered:
            guard !hasConfirmedVideo else { return }
            hasConfirmedVideo = true
            mediaWatchdog?.cancel()
            mediaWatchdog = nil
            emit(.videoConfirmed)
        }
    }

    private func handle(connectionState state: PeerConnectionState) {
        update(status: state.deviceStatus)

        switch state {
        case .connected:
            if let sessionId {
                Task { try? await self.transport.updateState(sessionId: sessionId, state: .connected) }
            }
            startMediaWatchdogIfNeeded()

        case .failed:
            mediaWatchdog?.cancel()
            if let sessionId {
                Task { try? await self.transport.updateState(sessionId: sessionId, state: .failed) }
            }
            report(.iceNegotiationFailed(turnConfigured: WebRTCConfiguration.current.hasTurnServer))

        case .disconnected:
            // Not terminal: WebRTC retries, and `.reconnecting` is already
            // reflected in the status above. Only `.failed` is final.
            report(.connectionLost)

        case .new, .connecting, .closed:
            break
        }
    }

    /// Starts the "connected but is video actually arriving?" check.
    ///
    /// Only the controller runs it - the camera is send-only and never
    /// expects frames. Without this, a session where SDP and ICE succeed but
    /// the camera is producing nothing would sit there reading "Connected"
    /// over a black rectangle, which is the single most misleading thing a
    /// WebRTC prototype can do.
    private func startMediaWatchdogIfNeeded() {
        guard role == .caller, !hasConfirmedVideo, mediaWatchdog == nil else { return }
        let gracePeriod = mediaGracePeriod
        mediaWatchdog = Task { [weak self] in
            try? await Task.sleep(for: gracePeriod)
            guard !Task.isCancelled, let self, !self.hasConfirmedVideo else { return }
            self.report(.mediaNeverArrived)
        }
    }

    // MARK: - Sending

    func send(_ message: RemoteControlMessage) throws {
        guard let peer else {
            throw RemoteCameraError.snapshotTransferFailed(reason: "there is no open connection")
        }
        try peer.sendControl(message)
    }

    func sendImage(frames: [Data]) async throws {
        guard let peer else {
            throw RemoteCameraError.snapshotTransferFailed(reason: "there is no open connection")
        }
        try await peer.sendBinary(frames: frames)
    }

    // MARK: - Teardown

    /// Ends the session from this side: tells the peer, marks the document
    /// closed, deletes it, and closes the connection.
    func disconnect(reason: String = "the session was ended") async {
        guard !isTearingDown else { return }
        isTearingDown = true

        // Best-effort courtesy frame so the peer shows "Disconnected"
        // immediately instead of waiting out an ICE timeout.
        try? peer?.sendControl(.sessionEnd(reason: reason))

        let closingSessionId = sessionId
        if let closingSessionId {
            try? await transport.updateState(sessionId: closingSessionId, state: .closed)
            try? await transport.deleteSession(sessionId: closingSessionId)
        }
        isTearingDown = false
        finishTeardown(reason: reason)
    }

    /// Releases everything local. Safe to call repeatedly.
    private func finishTeardown(reason: String) {
        let wasActive = sessionId != nil || peer != nil

        mediaWatchdog?.cancel()
        mediaWatchdog = nil
        sessionSubscription?.cancel()
        sessionSubscription = nil
        candidateSubscription?.cancel()
        candidateSubscription = nil
        peer?.close()
        peer = nil
        sessionId = nil
        peerDeviceId = nil
        queuedRemoteCandidates.removeAll()
        pendingLocalCandidates.removeAll()
        isSessionPublished = false
        hasRemoteDescription = false
        hasConfirmedVideo = false

        guard wasActive else { return }
        update(status: .disconnected)
        emit(.ended(reason: reason))
    }

    /// Stops listening for new sessions. Separate from `disconnect` so
    /// leaving Camera Mode can stop advertising without implying a session
    /// was in progress.
    func stopListening() {
        incomingSubscription?.cancel()
        incomingSubscription = nil
    }

    private func failSession(with error: Error) async {
        let remoteError = (error as? RemoteCameraError) ?? .signalingUnavailable(reason: error.localizedDescription)
        report(remoteError)
        if let sessionId {
            try? await transport.updateState(sessionId: sessionId, state: .failed)
        }
        update(status: .failed)
    }

    private func update(status newStatus: DeviceConnectionStatus) {
        guard status != newStatus else { return }
        status = newStatus
        emit(.statusChanged(newStatus))
    }

    private func report(_ error: RemoteCameraError) {
        logger.error("Session error: \(String(describing: error), privacy: .public)")
        emit(.failed(error))
    }

    /// Overload for the listener callbacks, which hand back an opaque `Error`
    /// from Firestore.
    private func report(underlying error: Error) {
        report((error as? RemoteCameraError) ?? .signalingUnavailable(reason: error.localizedDescription))
    }

    private func emit(_ event: Event) {
        onEvent?(event)
    }
}
