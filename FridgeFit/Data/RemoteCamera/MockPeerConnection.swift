//
//  MockPeerConnection.swift
//  FridgeFit
//

import Foundation

/// A `PeerConnectionControlling` test double that can be wired to another
/// instance to form a working pair.
///
/// Two of these plus one `InMemorySignalingTransport` give a complete
/// offer/answer/ICE/data-channel round trip with no WebRTC framework, no
/// camera and no network - which is what makes the negotiation ordering in
/// `WebRTCSessionCoordinator` testable at all.
///
/// Lives in the app target beside the real `WebRTCClient` for the same
/// reason `InMemoryPantryRepository` does: when the protocol changes, both
/// conformances get updated together.
@MainActor
final class MockPeerConnection: PeerConnectionControlling {
    var events: ((PeerConnectionEvent) -> Void)?

    /// The instance on the other end. Weak so a linked pair doesn't retain
    /// each other past the test.
    private(set) weak var linkedPeer: MockPeerConnection?

    private(set) var startedRole: SignalingRole?
    private(set) var remoteDescriptions: [SessionDescriptionPayload] = []
    private(set) var remoteCandidates: [IceCandidatePayload] = []
    private(set) var sentControlMessages: [RemoteControlMessage] = []
    private(set) var sentBinaryFrames: [Data] = []
    private(set) var isChannelOpen = false
    private(set) var isClosed = false

    /// Set to make `createOffer`/`createAnswer` throw, for the negotiation
    /// failure path.
    var negotiationFailure: Error?

    /// How many ICE candidates to emit when a local description is created.
    var candidatesToEmitPerDescription = 1

    private let identifier: String

    init(identifier: String = UUID().uuidString) {
        self.identifier = identifier
    }

    /// Wires two mocks together so control and binary frames sent on one
    /// arrive as events on the other.
    static func link(_ first: MockPeerConnection, _ second: MockPeerConnection) {
        first.linkedPeer = second
        second.linkedPeer = first
    }

    // MARK: - PeerConnectionControlling

    func start(role: SignalingRole) throws {
        startedRole = role
        events?(.connectionState(.new))
    }

    func createOffer() async throws -> SessionDescriptionPayload {
        if let negotiationFailure { throw negotiationFailure }
        emitLocalCandidates()
        return SessionDescriptionPayload(kind: .offer, sdp: "mock-offer-\(identifier)")
    }

    func createAnswer() async throws -> SessionDescriptionPayload {
        if let negotiationFailure { throw negotiationFailure }
        emitLocalCandidates()
        return SessionDescriptionPayload(kind: .answer, sdp: "mock-answer-\(identifier)")
    }

    func setRemoteDescription(_ payload: SessionDescriptionPayload) async throws {
        remoteDescriptions.append(payload)
    }

    func addRemoteCandidate(_ payload: IceCandidatePayload) async throws {
        remoteCandidates.append(payload)
    }

    func sendControl(_ message: RemoteControlMessage) throws {
        guard isChannelOpen else {
            throw RemoteCameraError.snapshotTransferFailed(reason: "the control channel is not open")
        }
        sentControlMessages.append(message)
        linkedPeer?.events?(.controlMessage(message))
    }

    func sendBinary(frames: [Data]) async throws {
        guard isChannelOpen else {
            throw RemoteCameraError.snapshotTransferFailed(reason: "the control channel is not open")
        }
        for frame in frames {
            sentBinaryFrames.append(frame)
            linkedPeer?.events?(.binaryFrame(frame))
        }
    }

    func close() {
        // Handler cleared before anything else, matching `WebRTCClient.close`
        // - a close that emitted events would re-enter the coordinator's
        // teardown.
        events = nil
        isClosed = true
        isChannelOpen = false
    }

    // MARK: - Test drivers

    /// Brings both ends up: data channel open, then ICE connected.
    func simulateConnected() {
        isChannelOpen = true
        linkedPeer?.isChannelOpen = true
        events?(.dataChannelOpen)
        linkedPeer?.events?(.dataChannelOpen)
        events?(.connectionState(.connected))
        linkedPeer?.events?(.connectionState(.connected))
    }

    func simulate(connectionState state: PeerConnectionState) {
        events?(.connectionState(state))
    }

    func simulateRemoteVideoTrackAdded() {
        events?(.remoteVideoTrackAdded)
    }

    func simulateFirstFrameRendered() {
        events?(.firstRemoteFrameRendered)
    }

    func simulateMalformedControlMessage(reason: String = "frame was not a JSON object") {
        events?(.malformedControlMessage(reason: reason))
    }

    func emitLocalCandidates() {
        for index in 0..<candidatesToEmitPerDescription {
            events?(.localCandidate(IceCandidatePayload(
                candidate: "candidate:\(identifier)-\(index) 1 udp 2130706431 192.168.1.9 50000 typ host",
                sdpMid: "0",
                sdpMLineIndex: 0
            )))
        }
    }
}
