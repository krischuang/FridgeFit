//
//  PeerConnectionControlling.swift
//  FridgeFit
//

import Foundation

/// The subset of `RTCPeerConnection` lifecycle the app reacts to.
///
/// Collapses WebRTC's two overlapping state machines (`RTCIceConnectionState`
/// and `RTCPeerConnectionState`) into the handful of cases the UI
/// distinguishes.
nonisolated enum PeerConnectionState: Equatable, Sendable {
    case new
    /// ICE is checking candidate pairs.
    case connecting
    /// A candidate pair is working. Media *should* flow - but note that
    /// `.connected` here is not the same as "video is on screen", which is
    /// why `PeerConnectionEvent.firstRemoteFrameRendered` exists separately.
    case connected
    /// Was connected, lost the path. WebRTC may still recover it.
    case disconnected
    /// ICE gave up. Not recoverable without renegotiating.
    case failed
    case closed

    var deviceStatus: DeviceConnectionStatus {
        switch self {
        case .new: return .connecting
        case .connecting: return .connecting
        case .connected: return .connected
        case .disconnected: return .reconnecting
        case .failed: return .failed
        case .closed: return .disconnected
        }
    }
}

/// Something the peer connection reported.
nonisolated enum PeerConnectionEvent: Sendable {
    /// A locally gathered ICE candidate, to be published to the peer.
    case localCandidate(IceCandidatePayload)
    case connectionState(PeerConnectionState)
    /// The data channel is open in both directions.
    case dataChannelOpen
    case dataChannelClosed
    case controlMessage(RemoteControlMessage)
    /// A control frame arrived that couldn't be parsed. Reported rather than
    /// thrown so a bad frame is visible in logs without killing the channel.
    case malformedControlMessage(reason: String)
    /// A binary frame, expected to be an `ImageTransferFrame`.
    case binaryFrame(Data)
    /// A remote video track was added to the connection. Means SDP
    /// negotiated video - not that any pixels have arrived.
    case remoteVideoTrackAdded
    /// The first actual frame was decoded and rendered. This is the only
    /// event that proves video is really flowing.
    case firstRemoteFrameRendered
}

/// A WebRTC peer connection, behind a protocol.
///
/// Exists so `WebRTCSessionCoordinator` - which owns the negotiation
/// ordering rules, the glare avoidance and the teardown - can be unit tested
/// against `MockPeerConnection` with no WebRTC framework, no camera and no
/// network. `WebRTCClient` is the only conformance that touches the SDK.
@MainActor
protocol PeerConnectionControlling: AnyObject {
    /// Set before `start`. Called on the main actor.
    var events: ((PeerConnectionEvent) -> Void)? { get set }

    /// Builds the peer connection.
    ///
    /// `role` decides who creates the data channel: the caller opens it, the
    /// callee waits for `didOpenDataChannel`. Both sides creating one would
    /// leave two half-used channels.
    func start(role: SignalingRole) throws

    func createOffer() async throws -> SessionDescriptionPayload
    func createAnswer() async throws -> SessionDescriptionPayload
    func setRemoteDescription(_ payload: SessionDescriptionPayload) async throws
    func addRemoteCandidate(_ payload: IceCandidatePayload) async throws

    /// Sends a JSON control frame. Throws if the channel isn't open.
    func sendControl(_ message: RemoteControlMessage) throws

    /// Sends binary frames, respecting the channel's buffer.
    ///
    /// Async because a whole image is more than the channel will take at
    /// once; the implementation waits for `bufferedAmount` to drain between
    /// chunks rather than dropping them.
    func sendBinary(frames: [Data]) async throws

    func close()
}
