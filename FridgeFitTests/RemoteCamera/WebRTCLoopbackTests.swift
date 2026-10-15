//
//  WebRTCLoopbackTests.swift
//  FridgeFitTests
//

import UIKit
import XCTest
@preconcurrency import WebRTC
@testable import FridgeFit

/// The real WebRTC stack, both ends in one process.
///
/// Everywhere else the SDK is behind `MockPeerConnection`, which proves the
/// *logic* around WebRTC is right but says nothing about whether the SDK
/// integration works. These tests use two genuine `WebRTCClient`s -
/// `RTCPeerConnectionFactory`, real SDP, real ICE, real SCTP data channel,
/// real VP8/H.264 encode and decode - connecting over host candidates on the
/// loopback interface, with `InMemorySignalingTransport` standing in for
/// Firestore and `SyntheticVideoSource` standing in for the camera.
///
/// What this covers that the mock tests cannot: that the SDP the app
/// generates actually negotiates, that the controller's `recvOnly`
/// transceiver really does give the camera somewhere to attach its track,
/// that frames really arrive and `FirstFrameSentinel` really fires, and that
/// a chunked JPEG really survives the data channel.
///
/// What it still cannot cover: NAT traversal, STUN, TURN, or anything about
/// two separate devices on a network. Loopback is the easiest possible ICE
/// case. Those remain real-device tests.
@MainActor
final class WebRTCLoopbackTests: XCTestCase {

    /// Generous because this is a real negotiation plus a real codec
    /// handshake. On a warm simulator it completes well inside a second.
    private let connectTimeout = Duration.seconds(15)

    private var videoSource: SyntheticVideoSource?
    private var controllerClient: WebRTCClient?
    private var cameraClient: WebRTCClient?

    override func tearDown() async throws {
        videoSource?.stop()
        videoSource = nil
        controllerClient?.close()
        cameraClient?.close()
        controllerClient = nil
        cameraClient = nil
        try await super.tearDown()
    }

    private struct Loopback {
        let transport: InMemorySignalingTransport
        let controller: WebRTCSessionCoordinator
        let camera: WebRTCSessionCoordinator
        let controllerEvents: EventLog
        let cameraEvents: EventLog
    }

    private final class EventLog {
        var events: [WebRTCSessionCoordinator.Event] = []

        var statuses: [DeviceConnectionStatus] {
            events.compactMap { if case .statusChanged(let s) = $0 { return s } else { return nil } }
        }
        var controlMessages: [RemoteControlMessage] {
            events.compactMap { if case .controlMessage(let m) = $0 { return m } else { return nil } }
        }
        var binaryFrames: [Data] {
            events.compactMap { if case .binaryFrame(let d) = $0 { return d } else { return nil } }
        }
        var sawVideo: Bool {
            events.contains { if case .videoConfirmed = $0 { return true } else { return false } }
        }
        var failures: [RemoteCameraError] {
            events.compactMap { if case .failed(let e) = $0 { return e } else { return nil } }
        }
    }

    /// Builds both ends with real `WebRTCClient`s and a synthetic camera.
    private func makeLoopback(withVideo: Bool) -> Loopback {
        let transport = InMemorySignalingTransport()
        let controllerIdentity = DeviceIdentity(deviceId: "loopback-controller", deviceName: "Controller")
        let cameraIdentity = DeviceIdentity(deviceId: "loopback-camera", deviceName: "Camera")

        var localTrack: RTCVideoTrack?
        if withVideo {
            let source = SyntheticVideoSource()
            source.start()
            videoSource = source
            localTrack = source.videoTrack
        }

        let controllerClient = WebRTCClient(
            // STUN is pointless on loopback and only adds gathering latency.
            configuration: WebRTCConfiguration(stunURLs: [], turnServer: nil)
        )
        let cameraClient = WebRTCClient(
            configuration: WebRTCConfiguration(stunURLs: [], turnServer: nil),
            localVideoTrack: localTrack
        )
        self.controllerClient = controllerClient
        self.cameraClient = cameraClient

        let controller = WebRTCSessionCoordinator(
            identity: controllerIdentity,
            role: .caller,
            transport: transport,
            makePeerConnection: { controllerClient },
            mediaGracePeriod: .seconds(20)
        )
        let camera = WebRTCSessionCoordinator(
            identity: cameraIdentity,
            role: .callee,
            transport: transport,
            makePeerConnection: { cameraClient },
            mediaGracePeriod: .seconds(20)
        )

        let controllerLog = EventLog()
        let cameraLog = EventLog()
        controller.setEventHandler { controllerLog.events.append($0) }
        camera.setEventHandler { cameraLog.events.append($0) }

        return Loopback(
            transport: transport,
            controller: controller,
            camera: camera,
            controllerEvents: controllerLog,
            cameraEvents: cameraLog
        )
    }

    private func connect(_ loopback: Loopback) async -> Bool {
        loopback.camera.startListeningForIncomingSessions()
        await loopback.controller.connect(
            toCameraDeviceId: "loopback-camera",
            cameraDeviceName: "Camera"
        )
        return await waitUntil(timeout: connectTimeout) {
            loopback.controller.status == .connected && loopback.camera.status == .connected
        }
    }

    /// Connects, or fails the test and skips the rest of it.
    ///
    /// Without the skip, one failed connection cascades into a thrown
    /// "channel is not open" from every later step, which buries the single
    /// failure that actually matters.
    private func requireConnected(_ loopback: Loopback) async throws {
        guard await connect(loopback) else {
            let detail = "controller: \(loopback.controller.status), camera: \(loopback.camera.status)"
            XCTFail("real ICE did not connect on loopback - \(detail), failures: \(loopback.controllerEvents.failures)")
            throw XCTSkip("no connection")
        }
    }

    /// Waits for the SCTP channel, which opens shortly after ICE connects.
    ///
    /// Probing by sending a `ping` is the honest test of "open" - the channel
    /// reporting itself open but refusing data would be a lie worth catching.
    /// - Parameter sender: the side the test is about to send from.
    ///
    /// Which side matters. The caller creates the data channel, so its end
    /// reports open first; the callee's arrives separately via
    /// `didOpenDataChannel` and can lag behind. Probing the controller and
    /// then sending from the camera is a race that only shows up when the
    /// machine is busy.
    private func requireOpenDataChannel(
        _ loopback: Loopback,
        from sender: Sender = .controller
    ) async throws {
        let coordinator = sender == .controller ? loopback.controller : loopback.camera
        let ready = await waitUntil(timeout: connectTimeout) {
            (try? coordinator.send(.ping)) != nil
        }
        guard ready else {
            XCTFail("the \(sender) data channel never opened")
            throw XCTSkip("no data channel")
        }
    }

    private enum Sender: String { case controller, camera }

    /// Sends until the far side sees it, or the timeout expires.
    ///
    /// SCTP delivery is reliable once both ends are up, but a message sent in
    /// the window between the local channel reporting open and the remote
    /// delegate being attached is simply dropped. Retrying closes that window
    /// without weakening what is being asserted.
    @discardableResult
    private func deliver(
        timeout: Duration = .seconds(10),
        send: () -> Void,
        until received: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if received() { return true }
            send()
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(25))
        }
        return received()
    }

    // MARK: - Real negotiation

    func test_twoRealPeerConnections_negotiateAndConnect() async throws {
        let loopback = makeLoopback(withVideo: true)

        let connected = await connect(loopback)

        XCTAssertTrue(
            connected,
            """
            Real ICE did not connect on loopback. Controller: \
            \(loopback.controller.status), camera: \(loopback.camera.status), \
            failures: \(loopback.controllerEvents.failures)
            """
        )
        XCTAssertEqual(loopback.controller.status, .connected)
        XCTAssertEqual(loopback.camera.status, .connected)

        // The session document is written from a detached task so ICE
        // progress is never blocked on Firestore, so wait for it rather than
        // assuming it landed by the time the local status flipped.
        let documentCaughtUp = await waitUntil(timeout: connectTimeout) {
            loopback.transport.storedSession(at: 0)?.state == .connected
        }
        XCTAssertTrue(documentCaughtUp, "the signaling document never reached connected")
    }

    func test_theOfferAndAnswerAreRealSdp() async throws {
        let loopback = makeLoopback(withVideo: true)
        try await requireConnected(loopback)

        let session = try XCTUnwrap(loopback.transport.storedSessions.first)
        let offer = try XCTUnwrap(session.offer?.sdp)
        let answer = try XCTUnwrap(session.answer?.sdp)

        XCTAssertTrue(offer.hasPrefix("v=0"), "an offer should be an SDP blob")
        XCTAssertTrue(offer.contains("m=video"), "the controller must offer a video m-line")
        XCTAssertTrue(
            offer.contains("a=recvonly"),
            "the controller is receive-only, so its video m-line should say so"
        )
        XCTAssertTrue(offer.contains("m=application"), "the data channel needs an SCTP m-line")
        XCTAssertTrue(answer.contains("m=video"))
        XCTAssertTrue(
            answer.contains("a=sendonly"),
            "the camera answers send-only, which is what proves its track attached"
        )
    }

    func test_realIceCandidatesAreExchangedThroughSignaling() async throws {
        let loopback = makeLoopback(withVideo: true)
        try await requireConnected(loopback)
        let sessionId = try XCTUnwrap(loopback.transport.storedSessions.first?.sessionId)
        // Candidates are published from detached tasks too.
        _ = await waitUntil(timeout: connectTimeout) {
            !loopback.transport.storedCandidates(sessionId: sessionId, from: .caller).isEmpty
                && !loopback.transport.storedCandidates(sessionId: sessionId, from: .callee).isEmpty
        }

        let callerCandidates = loopback.transport.storedCandidates(sessionId: sessionId, from: .caller)
        let calleeCandidates = loopback.transport.storedCandidates(sessionId: sessionId, from: .callee)

        XCTAssertFalse(callerCandidates.isEmpty)
        XCTAssertFalse(calleeCandidates.isEmpty)
        XCTAssertTrue(
            callerCandidates.contains { $0.candidate.contains("typ host") },
            "loopback should produce host candidates: \(callerCandidates.map(\.candidate))"
        )
    }

    // MARK: - Real media

    /// The claim the whole prototype rests on: frames encoded on one peer
    /// are decoded on the other.
    func test_realVideoFramesReachTheController() async throws {
        let loopback = makeLoopback(withVideo: true)
        try await requireConnected(loopback)

        let sawVideo = await waitUntil(timeout: connectTimeout) {
            loopback.controllerEvents.sawVideo
        }

        XCTAssertTrue(
            sawVideo,
            "no decoded frame arrived - failures: \(loopback.controllerEvents.failures)"
        )
        XCTAssertNotNil(controllerClient?.remoteVideoTrack, "the remote track should be attachable to a view")
    }

    /// The honesty check, against the real SDK: with the camera publishing no
    /// track, ICE still connects and the app must still refuse to claim video.
    func test_aConnectionWithNoCameraTrackNeverConfirmsVideo() async throws {
        let loopback = makeLoopback(withVideo: false)
        try await requireConnected(loopback)

        // Long enough for frames to have arrived if any were coming.
        try? await Task.sleep(for: .seconds(2))

        XCTAssertFalse(
            loopback.controllerEvents.sawVideo,
            "ICE connecting must never be reported as video arriving"
        )
    }

    // MARK: - Real data channel

    func test_controlMessagesCrossTheRealDataChannel() async throws {
        let loopback = makeLoopback(withVideo: true)
        try await requireConnected(loopback)
        // `connected` is ICE; the SCTP channel opens a moment later.
        // Both ends, because this test sends in both directions.
        try await requireOpenDataChannel(loopback, from: .camera)
        try await requireOpenDataChannel(loopback)

        let gotPing = await deliver(
            send: { try? loopback.controller.send(.ping) },
            until: { loopback.cameraEvents.controlMessages.contains(.ping) }
        )
        XCTAssertTrue(gotPing, "the camera never received the ping")

        let gotPong = await deliver(
            send: { try? loopback.camera.send(.pong) },
            until: { loopback.controllerEvents.controlMessages.contains(.pong) }
        )
        XCTAssertTrue(gotPong, "the controller never received the pong")
    }

    func test_aMalformedFrameOnTheRealChannelIsDroppedNotFatal() async throws {
        let loopback = makeLoopback(withVideo: true)
        try await requireConnected(loopback)
        try await requireOpenDataChannel(loopback)

        // Push raw non-JSON text through the real channel, bypassing the coder.
        try controllerClient?.sendRawTextFrame(Data("this is not json".utf8))
        try? await Task.sleep(for: .milliseconds(500))

        // Still usable afterwards.
        let stillWorks = await deliver(
            send: { try? loopback.controller.send(.capturePhoto(requestId: "after-garbage")) },
            until: { loopback.cameraEvents.controlMessages.contains(.capturePhoto(requestId: "after-garbage")) }
        )

        XCTAssertTrue(stillWorks, "a bad frame must not take the channel down")
        XCTAssertEqual(loopback.camera.status, .connected)
    }

    /// Test E against the real transport: a JPEG, chunked, pushed through
    /// SCTP with backpressure, reassembled, and decoded back to an image.
    func test_aRealJpegCrossesTheDataChannelAndDecodes() async throws {
        let loopback = makeLoopback(withVideo: true)
        try await requireConnected(loopback)
        // The camera is the sender here, so it is the camera's end of the
        // channel that has to be open.
        try await requireOpenDataChannel(loopback, from: .camera)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let original = UIGraphicsImageRenderer(
            size: CGSize(width: 1200, height: 900),
            format: format
        ).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 100, y: 100, width: 400, height: 300))
        }
        let payload = try SnapshotImageEncoder.encode(original)
        let transferId = UUID()
        let frames = try ImageTransferFrame.chunk(payload: payload, transferId: transferId)
        XCTAssertGreaterThan(frames.count, 1, "the fixture should need more than one chunk")

        try loopback.camera.send(.captureCompleted(
            requestId: "req-1",
            transferId: transferId.uuidString,
            byteCount: payload.count,
            chunkCount: frames.count
        ))
        try await loopback.camera.sendImage(frames: frames)

        let assembler = ImageTransferAssembler()
        var reassembled: Data?
        let arrived = await waitUntil(timeout: connectTimeout) {
            for frame in loopback.controllerEvents.binaryFrames.dropFirst(0) where reassembled == nil {
                if case .completed(_, let data) = assembler.accept(frame: frame) {
                    reassembled = data
                }
            }
            return reassembled != nil
        }

        XCTAssertTrue(
            arrived,
            """
            the image never fully arrived - got \
            \(loopback.controllerEvents.binaryFrames.count) of \(frames.count) chunks
            """
        )
        XCTAssertEqual(reassembled, payload, "the reassembled bytes must be identical")
        let decoded = try XCTUnwrap(SnapshotImageEncoder.decode(try XCTUnwrap(reassembled)))
        XCTAssertEqual(decoded.size.width, 1200, accuracy: 1)
        XCTAssertEqual(decoded.size.height, 900, accuracy: 1)
    }

    // MARK: - Teardown

    func test_disconnectingClosesBothRealPeerConnections() async throws {
        let loopback = makeLoopback(withVideo: true)
        try await requireConnected(loopback)

        await loopback.controller.disconnect(reason: "test teardown")
        _ = await waitUntil(timeout: connectTimeout) { loopback.camera.activeSessionId == nil }

        XCTAssertNil(loopback.controller.activeSessionId)
        XCTAssertNil(loopback.camera.activeSessionId)
        XCTAssertTrue(loopback.transport.storedSessions.isEmpty)
    }
}

// MARK: - Test-only hooks

extension InMemorySignalingTransport {
    func storedSession(at index: Int) -> WebRTCSessionRecord? {
        let sessions = storedSessions
        return index < sessions.count ? sessions[index] : nil
    }
}
