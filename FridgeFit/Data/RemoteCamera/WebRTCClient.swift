//
//  WebRTCClient.swift
//  FridgeFit
//

import Foundation
import OSLog
@preconcurrency import WebRTC

/// The only type in FridgeFit that touches `RTCPeerConnection`.
///
/// Everything above it - `WebRTCSessionCoordinator`, both view models - works
/// against `PeerConnectionControlling`, so the negotiation logic can be
/// tested without the SDK, a camera, or a network.
///
/// ## Threading
///
/// WebRTC calls its delegate on its own signaling and worker threads. This
/// class is `@MainActor`, and `PeerConnectionDelegateProxy` is the
/// `nonisolated` bridge that hops every callback onto the main actor before
/// it reaches any state here. Nothing in this file is touched from a WebRTC
/// thread.
@MainActor
final class WebRTCClient: PeerConnectionControlling {
    var events: ((PeerConnectionEvent) -> Void)?

    /// The remote track, once negotiated. `RemoteCameraView` attaches an
    /// `RTCMTLVideoView` to it.
    private(set) var remoteVideoTrack: RTCVideoTrack?

    /// Called when `remoteVideoTrack` becomes available, so a view that is
    /// already on screen can attach without polling.
    var onRemoteVideoTrack: ((RTCVideoTrack) -> Void)?

    private let configuration: WebRTCConfiguration
    /// Supplied by the camera device. `nil` on the controller, which is
    /// receive-only.
    private let localVideoTrack: RTCVideoTrack?
    private let logger = Logger(subsystem: "com.Fridge.FridgeFit", category: "WebRTCClient")

    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var delegateProxy: PeerConnectionDelegateProxy?
    private var firstFrameSentinel: FirstFrameSentinel?
    private var isClosed = false

    /// Label both ends open the channel with. The callee only accepts a
    /// channel with this label, so an unrelated channel can't be mistaken
    /// for the control one.
    static let dataChannelLabel = "fridgefit-control"

    /// Buffer level at which `sendBinary` pauses.
    ///
    /// SCTP will happily accept more than it can send and grow its send
    /// buffer until memory runs out. Pausing at 256 KB keeps a whole image
    /// in flight without that risk.
    private static let sendBufferHighWaterMark: UInt64 = 256 * 1024
    private static let sendBufferPollInterval = Duration.milliseconds(20)
    /// Total time `sendBinary` will wait on a stalled buffer before giving up.
    private static let sendBufferDrainTimeout = Duration.seconds(15)

    init(configuration: WebRTCConfiguration = .current, localVideoTrack: RTCVideoTrack? = nil) {
        self.configuration = configuration
        self.localVideoTrack = localVideoTrack
    }

    // MARK: - Lifecycle

    func start(role: SignalingRole) throws {
        guard peerConnection == nil else { return }

        let rtcConfiguration = RTCConfiguration()
        rtcConfiguration.iceServers = Self.iceServers(from: configuration)
        // Unified Plan is the standards-compliant semantics and the only one
        // where `addTransceiver` behaves as specified. Plan B is deprecated.
        rtcConfiguration.sdpSemantics = .unifiedPlan
        // Keep gathering after the initial pass so a network change (Wi-Fi to
        // cellular, or joining a different Wi-Fi) can still produce a usable
        // candidate instead of stranding the session.
        rtcConfiguration.continualGatheringPolicy = .gatherContinually
        rtcConfiguration.bundlePolicy = .maxBundle
        rtcConfiguration.rtcpMuxPolicy = .require

        let proxy = PeerConnectionDelegateProxy { [weak self] event in
            self?.handle(proxyEvent: event)
        }
        delegateProxy = proxy

        guard let connection = WebRTCFactory.shared.peerConnectionFactory.peerConnection(
            with: rtcConfiguration,
            constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil),
            delegate: proxy
        ) else {
            throw RemoteCameraError.signalingUnavailable(reason: "the WebRTC peer connection could not be created")
        }
        peerConnection = connection
        logger.info("Peer connection started as \(role.rawValue, privacy: .public). \(self.configuration.describedForLogs, privacy: .public)")

        switch role {
        case .caller:
            // Only the caller opens the data channel. If both sides opened
            // one, each would have a channel the other never reads.
            let channelConfiguration = RTCDataChannelConfiguration()
            // Ordered and reliable, so `ImageTransferAssembler` normally sees
            // chunks in sequence. It tolerates reordering anyway - relying on
            // the transport for correctness would make it fragile if this
            // config ever changed.
            channelConfiguration.isOrdered = true
            guard let channel = connection.dataChannel(
                forLabel: Self.dataChannelLabel,
                configuration: channelConfiguration
            ) else {
                throw RemoteCameraError.signalingUnavailable(reason: "the WebRTC data channel could not be created")
            }
            channel.delegate = proxy
            dataChannel = channel

            // The caller is receive-only for video, but it still has to put a
            // video m-line in the offer: the answerer cannot add one that
            // wasn't offered, so without this the camera would have nowhere
            // to attach its track.
            let transceiverInit = RTCRtpTransceiverInit()
            transceiverInit.direction = .recvOnly
            connection.addTransceiver(of: .video, init: transceiverInit)

        case .callee:
            // Added before any SDP so the incoming offer's video m-line
            // associates with this transceiver and the answer comes out
            // send-only.
            if let localVideoTrack {
                connection.add(localVideoTrack, streamIds: ["fridgefit-stream"])
            } else {
                logger.error("Starting as callee with no local video track - the controller will see no video")
            }
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true

        if let remoteVideoTrack, let firstFrameSentinel {
            remoteVideoTrack.remove(firstFrameSentinel)
        }
        firstFrameSentinel = nil
        dataChannel?.delegate = nil
        dataChannel?.close()
        dataChannel = nil
        peerConnection?.delegate = nil
        peerConnection?.close()
        peerConnection = nil
        delegateProxy = nil
        remoteVideoTrack = nil
        events = nil
        onRemoteVideoTrack = nil
    }

    /// Closes the peer connection without the main-actor hop an isolated
    /// deinit needs.
    ///
    /// Same reason as `DeviceHeartbeat` and `WebRTCSessionCoordinator`: an
    /// isolated `deinit` performed inside another one corrupts the
    /// concurrency runtime's task-local stack and aborts the process.
    ///
    /// `RTCPeerConnection.close()` is safe off the main actor - WebRTC
    /// marshals onto its own signaling thread - so this doubles as a
    /// backstop against leaking a peer connection and its worker threads if
    /// `close()` was never called.
    nonisolated deinit {
        guard !isClosed else { return }
        dataChannel?.delegate = nil
        dataChannel?.close()
        peerConnection?.delegate = nil
        peerConnection?.close()
    }

    // MARK: - Negotiation

    func createOffer() async throws -> SessionDescriptionPayload {
        guard let peerConnection else { throw RemoteCameraError.sessionExpired }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let offer: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            peerConnection.offer(for: constraints) { description, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let description {
                    continuation.resume(returning: description)
                } else {
                    continuation.resume(throwing: RemoteCameraError.signalingUnavailable(
                        reason: "WebRTC produced no offer"
                    ))
                }
            }
        }
        try await setLocal(offer)
        return SessionDescriptionPayload(kind: .offer, sdp: offer.sdp)
    }

    func createAnswer() async throws -> SessionDescriptionPayload {
        guard let peerConnection else { throw RemoteCameraError.sessionExpired }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let answer: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            peerConnection.answer(for: constraints) { description, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let description {
                    continuation.resume(returning: description)
                } else {
                    continuation.resume(throwing: RemoteCameraError.signalingUnavailable(
                        reason: "WebRTC produced no answer"
                    ))
                }
            }
        }
        try await setLocal(answer)
        return SessionDescriptionPayload(kind: .answer, sdp: answer.sdp)
    }

    private func setLocal(_ description: RTCSessionDescription) async throws {
        guard let peerConnection else { throw RemoteCameraError.sessionExpired }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setLocalDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func setRemoteDescription(_ payload: SessionDescriptionPayload) async throws {
        guard let peerConnection else { throw RemoteCameraError.sessionExpired }
        let description = RTCSessionDescription(
            type: payload.kind == .offer ? .offer : .answer,
            sdp: payload.sdp
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setRemoteDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func addRemoteCandidate(_ payload: IceCandidatePayload) async throws {
        guard let peerConnection else { throw RemoteCameraError.sessionExpired }
        let candidate = RTCIceCandidate(
            sdp: payload.candidate,
            sdpMLineIndex: Int32(payload.sdpMLineIndex),
            sdpMid: payload.sdpMid
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.add(candidate) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Data channel

    func sendControl(_ message: RemoteControlMessage) throws {
        guard let dataChannel, dataChannel.readyState == .open else {
            throw RemoteCameraError.snapshotTransferFailed(reason: "the control channel is not open")
        }
        let buffer = RTCDataBuffer(data: RemoteControlMessageCoder.encode(message), isBinary: false)
        guard dataChannel.sendData(buffer) else {
            throw RemoteCameraError.snapshotTransferFailed(reason: "the control channel rejected the message")
        }
    }

    /// Sends image frames, pausing whenever the channel's send buffer is
    /// full.
    ///
    /// Without the pause, pushing ~30 chunks back to back can overrun SCTP's
    /// buffer and have frames rejected mid-image, which shows up as a
    /// transfer that never completes.
    func sendBinary(frames: [Data]) async throws {
        guard let dataChannel, dataChannel.readyState == .open else {
            throw RemoteCameraError.snapshotTransferFailed(reason: "the control channel is not open")
        }

        for frame in frames {
            try await waitForSendBuffer(on: dataChannel)
            guard dataChannel.readyState == .open else {
                throw RemoteCameraError.snapshotTransferFailed(reason: "the connection closed mid-transfer")
            }
            guard dataChannel.sendData(RTCDataBuffer(data: frame, isBinary: true)) else {
                throw RemoteCameraError.snapshotTransferFailed(reason: "a chunk was rejected by the connection")
            }
        }
    }

    /// Sends a text frame without going through `RemoteControlMessageCoder`.
    ///
    /// Exists so `WebRTCLoopbackTests` can put a genuinely malformed frame on
    /// a real data channel and prove the receiver drops it instead of tearing
    /// the session down. The encoder cannot produce such a frame, so there is
    /// no other way to test that path end to end. Not used by the app.
    func sendRawTextFrame(_ data: Data) throws {
        guard let dataChannel, dataChannel.readyState == .open else {
            throw RemoteCameraError.snapshotTransferFailed(reason: "the control channel is not open")
        }
        guard dataChannel.sendData(RTCDataBuffer(data: data, isBinary: false)) else {
            throw RemoteCameraError.snapshotTransferFailed(reason: "the control channel rejected the frame")
        }
    }

    private func waitForSendBuffer(on channel: RTCDataChannel) async throws {
        var waited = Duration.zero
        while channel.bufferedAmount > Self.sendBufferHighWaterMark {
            guard waited < Self.sendBufferDrainTimeout else {
                throw RemoteCameraError.snapshotTransferFailed(reason: "the connection stopped draining")
            }
            try await Task.sleep(for: Self.sendBufferPollInterval)
            waited += Self.sendBufferPollInterval
        }
    }

    // MARK: - Delegate events

    private func handle(proxyEvent event: PeerConnectionDelegateProxy.Event) {
        guard !isClosed else { return }

        switch event {
        case .iceCandidate(let candidate):
            events?(.localCandidate(IceCandidatePayload(
                candidate: candidate.sdp,
                sdpMid: candidate.sdpMid,
                sdpMLineIndex: Int(candidate.sdpMLineIndex)
            )))

        case .connectionState(let state):
            events?(.connectionState(state))

        case .remoteDataChannel(let channel):
            // Callee side. Only the agreed label is accepted.
            guard channel.label == Self.dataChannelLabel else {
                logger.error("Ignoring unexpected data channel \"\(channel.label, privacy: .public)\"")
                return
            }
            channel.delegate = delegateProxy
            dataChannel = channel
            if channel.readyState == .open {
                events?(.dataChannelOpen)
            }

        case .dataChannelState(let state):
            switch state {
            case .open: events?(.dataChannelOpen)
            case .closed: events?(.dataChannelClosed)
            case .connecting, .closing: break
            @unknown default: break
            }

        case .dataChannelMessage(let data, let isBinary):
            if isBinary {
                events?(.binaryFrame(data))
            } else {
                switch RemoteControlMessageCoder.decode(data) {
                case .success(let message):
                    events?(.controlMessage(message))
                case .failure(let failure):
                    events?(.malformedControlMessage(reason: failure.describedReason))
                }
            }

        case .remoteVideoTrack(let track):
            remoteVideoTrack = track
            let sentinel = FirstFrameSentinel { [weak self] in
                self?.events?(.firstRemoteFrameRendered)
            }
            firstFrameSentinel = sentinel
            track.add(sentinel)
            events?(.remoteVideoTrackAdded)
            onRemoteVideoTrack?(track)
        }
    }

    private static func iceServers(from configuration: WebRTCConfiguration) -> [RTCIceServer] {
        var servers: [RTCIceServer] = []
        // An `RTCIceServer` with no URLs fails WebRTC's ICE server parsing
        // ("Empty uri"), and a configuration containing one makes
        // `peerConnection(with:...)` return nil - so an empty STUN list would
        // take the whole connection down rather than simply meaning "no STUN".
        if !configuration.stunURLs.isEmpty {
            servers.append(RTCIceServer(urlStrings: configuration.stunURLs))
        }
        if let turn = configuration.turnServer {
            servers.append(RTCIceServer(
                urlStrings: [turn.url],
                username: turn.username,
                credential: turn.credential
            ))
        }
        return servers
    }
}

/// Bridges WebRTC's delegate callbacks - which arrive on its signaling and
/// worker threads - onto the main actor.
///
/// `nonisolated` at the type level so the stored handler can be read from a
/// WebRTC thread; the handler itself is `@MainActor`, so every delivery goes
/// through a hop and `WebRTCClient` never sees a background thread.
nonisolated final class PeerConnectionDelegateProxy: NSObject,
                                                     RTCPeerConnectionDelegate,
                                                     RTCDataChannelDelegate,
                                                     @unchecked Sendable {
    /// `@unchecked` because the payloads are WebRTC's own Objective-C
    /// objects. They predate `Sendable` but are thread-safe by design - the
    /// SDK hands them to its delegate from its own threads expecting them to
    /// be used elsewhere - and each one is handed straight to the main actor
    /// without being mutated.
    nonisolated enum Event: @unchecked Sendable {
        case iceCandidate(RTCIceCandidate)
        case connectionState(PeerConnectionState)
        case remoteDataChannel(RTCDataChannel)
        case dataChannelState(RTCDataChannelState)
        case dataChannelMessage(Data, isBinary: Bool)
        case remoteVideoTrack(RTCVideoTrack)
    }

    private let handler: @MainActor (Event) -> Void

    init(handler: @escaping @MainActor (Event) -> Void) {
        self.handler = handler
        super.init()
    }

    private func forward(_ event: Event) {
        let deliver = handler
        Task { @MainActor in deliver(event) }
    }

    // MARK: - RTCPeerConnectionDelegate

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        forward(.iceCandidate(candidate))
    }

    /// The modern aggregate state. Preferred over `didChangeIceConnectionState`
    /// because it already folds in DTLS, so `.connected` here means the
    /// connection is genuinely usable.
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        forward(.connectionState(Self.map(newState)))
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        forward(.remoteDataChannel(dataChannel))
    }

    /// Unified Plan's "a remote track arrived" callback.
    func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd rtpReceiver: RTCRtpReceiver,
        streams mediaStreams: [RTCMediaStream]
    ) {
        guard let track = rtpReceiver.track as? RTCVideoTrack else { return }
        forward(.remoteVideoTrack(track))
    }

    // Required by the protocol, unused under Unified Plan.
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    // MARK: - RTCDataChannelDelegate

    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        forward(.dataChannelState(dataChannel.readyState))
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        forward(.dataChannelMessage(buffer.data, isBinary: buffer.isBinary))
    }

    // MARK: - State mapping

    static func map(_ state: RTCPeerConnectionState) -> PeerConnectionState {
        switch state {
        case .new: return .new
        case .connecting: return .connecting
        case .connected: return .connected
        case .disconnected: return .disconnected
        case .failed: return .failed
        case .closed: return .closed
        @unknown default: return .new
        }
    }
}
