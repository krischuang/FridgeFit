//
//  WebRTCSessionCoordinatorTests.swift
//  FridgeFitTests
//

import FirebaseFirestore
import XCTest
@testable import FridgeFit

/// Test C: session signaling - offer creation, answer handling, ICE
/// candidate exchange, state transitions and cleanup - driven through two
/// real coordinators over one in-memory transport.
@MainActor
final class WebRTCSessionCoordinatorTests: XCTestCase {

    // MARK: - Offer / answer

    func test_negotiation_completesOfferAndAnswer() async throws {
        let harness = SignalingHarness()

        let negotiated = await harness.negotiate()
        let sessionId = try XCTUnwrap(negotiated)

        let session = try XCTUnwrap(harness.storedSession)
        XCTAssertEqual(session.sessionId, sessionId)
        XCTAssertEqual(session.state, .answering)
        XCTAssertEqual(session.offer?.kind, .offer)
        XCTAssertEqual(session.answer?.kind, .answer)
        XCTAssertEqual(session.callerDeviceId, "device-controller")
        XCTAssertEqual(session.calleeDeviceId, "device-camera")
    }

    /// The glare-avoidance property: only the controller ever creates an
    /// offer, so there is no simultaneous-offer case to resolve.
    func test_onlyTheControllerCreatesAnOffer() async throws {
        let harness = SignalingHarness()

        await harness.negotiate()

        XCTAssertEqual(harness.controllerPeer.startedRole, .caller)
        XCTAssertEqual(harness.cameraPeer.startedRole, .callee)
        XCTAssertEqual(harness.cameraPeer.remoteDescriptions.map(\.kind), [.offer])
        XCTAssertEqual(harness.controllerPeer.remoteDescriptions.map(\.kind), [.answer])
    }

    func test_theCameraAppliesTheOfferBeforeAnswering() async throws {
        let harness = SignalingHarness()

        await harness.negotiate()

        // An answer built before the offer was applied would have the wrong
        // media directions, so the ordering is the thing being asserted.
        XCTAssertFalse(harness.cameraPeer.remoteDescriptions.isEmpty)
        XCTAssertEqual(harness.storedSession?.answer?.sdp, "mock-answer-camera")
    }

    func test_aDuplicateSessionSnapshot_doesNotReapplyTheAnswer() async throws {
        let harness = SignalingHarness()
        let negotiated = await harness.negotiate()
        let sessionId = try XCTUnwrap(negotiated)

        // Re-delivering the same document, which a Firestore listener does on
        // any unrelated field change.
        try await harness.transport.updateState(sessionId: sessionId, state: .connected)
        await waitUntil { harness.storedSession?.state == .connected }

        XCTAssertEqual(
            harness.controllerPeer.remoteDescriptions.count,
            1,
            "the answer must be applied exactly once"
        )
    }

    // MARK: - ICE candidate exchange

    func test_bothSidesPublishAndReceiveIceCandidates() async throws {
        let harness = SignalingHarness()
        let negotiated = await harness.negotiate()
        let sessionId = try XCTUnwrap(negotiated)

        await waitUntil {
            !harness.controllerPeer.remoteCandidates.isEmpty && !harness.cameraPeer.remoteCandidates.isEmpty
        }

        XCTAssertFalse(
            harness.transport.storedCandidates(sessionId: sessionId, from: .caller).isEmpty,
            "the controller should have published its candidates"
        )
        XCTAssertFalse(
            harness.transport.storedCandidates(sessionId: sessionId, from: .callee).isEmpty,
            "the camera should have published its candidates"
        )
        XCTAssertFalse(
            harness.controllerPeer.remoteCandidates.isEmpty,
            "the controller should have applied the camera's candidates"
        )
        XCTAssertFalse(
            harness.cameraPeer.remoteCandidates.isEmpty,
            "the camera should have applied the controller's candidates"
        )
    }

    func test_eachSideReceivesTheOthersCandidatesNotItsOwn() async throws {
        let harness = SignalingHarness()
        await harness.negotiate()
        await waitUntil { !harness.cameraPeer.remoteCandidates.isEmpty }

        for candidate in harness.cameraPeer.remoteCandidates {
            XCTAssertTrue(
                candidate.candidate.contains("controller"),
                "the camera must only apply the controller's candidates"
            )
        }
        for candidate in harness.controllerPeer.remoteCandidates {
            XCTAssertTrue(
                candidate.candidate.contains("camera"),
                "the controller must only apply the camera's candidates"
            )
        }
    }

    /// Candidates that arrive before the remote description must be queued,
    /// not dropped - `addIceCandidate` is only legal afterwards, and dropping
    /// them is a classic "connects most of the time" bug.
    func test_candidatesArrivingBeforeTheRemoteDescription_areQueuedThenApplied() async throws {
        let harness = SignalingHarness()
        harness.controllerPeer.candidatesToEmitPerDescription = 3

        await harness.negotiate()
        await waitUntil { harness.cameraPeer.remoteCandidates.count == 3 }

        XCTAssertEqual(
            harness.cameraPeer.remoteCandidates.count,
            3,
            "every candidate the controller published must reach the camera"
        )
    }

    // MARK: - State transitions

    func test_sessionReachesConnectedWhenIceConnects() async throws {
        let harness = SignalingHarness()
        await harness.negotiate()

        harness.controllerPeer.simulateConnected()
        await waitUntil { harness.storedSession?.state == .connected }

        XCTAssertEqual(harness.storedSession?.state, .connected)
        XCTAssertEqual(harness.controller.status, .connected)
        XCTAssertEqual(harness.camera.status, .connected)
    }

    func test_theLegalTransitionSequence() {
        XCTAssertTrue(WebRTCSessionState.creating.canTransition(to: .offering))
        XCTAssertTrue(WebRTCSessionState.offering.canTransition(to: .answering))
        XCTAssertTrue(WebRTCSessionState.answering.canTransition(to: .connected))
    }

    func test_anySessionCanBeClosedOrFailed() {
        for state in WebRTCSessionState.allCases where !state.isTerminal {
            XCTAssertTrue(state.canTransition(to: .closed), "\(state) should be closable")
            XCTAssertTrue(state.canTransition(to: .failed), "\(state) should be failable")
        }
    }

    func test_transitionsCannotRunBackwards() {
        XCTAssertFalse(WebRTCSessionState.connected.canTransition(to: .offering))
        XCTAssertFalse(WebRTCSessionState.answering.canTransition(to: .offering))
        XCTAssertFalse(WebRTCSessionState.offering.canTransition(to: .creating))
    }

    func test_aTerminalSessionCannotBeReopened() {
        for terminal in [WebRTCSessionState.closed, .failed] {
            for next in WebRTCSessionState.allCases {
                XCTAssertFalse(
                    terminal.canTransition(to: next),
                    "\(terminal) must not transition to \(next)"
                )
            }
        }
    }

    func test_aRedundantSameStateWriteIsNotATransition() {
        for state in WebRTCSessionState.allCases {
            XCTAssertFalse(state.canTransition(to: state))
        }
    }

    func test_theTransportRefusesAnIllegalTransition() async throws {
        let harness = SignalingHarness()
        let negotiated = await harness.negotiate()
        let sessionId = try XCTUnwrap(negotiated)

        // answering -> offering is backwards.
        try await harness.transport.updateState(sessionId: sessionId, state: .offering)

        XCTAssertEqual(harness.storedSession?.state, .answering)
        XCTAssertEqual(harness.transport.rejectedTransitions.count, 1)
        XCTAssertEqual(harness.transport.rejectedTransitions.first?.from, .answering)
        XCTAssertEqual(harness.transport.rejectedTransitions.first?.to, .offering)
    }

    func test_sessionStateMapsToTheDisplayedStatus() {
        XCTAssertEqual(WebRTCSessionState.creating.deviceStatus, .connecting)
        XCTAssertEqual(WebRTCSessionState.offering.deviceStatus, .connecting)
        XCTAssertEqual(WebRTCSessionState.answering.deviceStatus, .connecting)
        XCTAssertEqual(WebRTCSessionState.connected.deviceStatus, .connected)
        XCTAssertEqual(WebRTCSessionState.closed.deviceStatus, .disconnected)
        XCTAssertEqual(WebRTCSessionState.failed.deviceStatus, .failed)
    }

    // MARK: - Cleanup

    func test_disconnect_closesAndDeletesTheSession() async throws {
        let harness = SignalingHarness()
        await harness.negotiate()
        harness.controllerPeer.simulateConnected()
        await waitUntil { harness.storedSession?.state == .connected }

        await harness.controller.disconnect(reason: "test teardown")

        XCTAssertTrue(harness.transport.storedSessions.isEmpty, "the session document should be gone")
        XCTAssertFalse(harness.transport.hasAnyStoredCandidates, "candidate subcollections should be gone too")
        XCTAssertNil(harness.controller.activeSessionId)
        XCTAssertTrue(harness.controllerPeer.isClosed)
    }

    /// Error case 7: the controller vanishes. The camera learns about it from
    /// the `session_end` frame rather than waiting out an ICE timeout.
    func test_theCameraIsToldWhenTheControllerDisconnects() async throws {
        let harness = SignalingHarness()
        await harness.negotiate()
        harness.controllerPeer.simulateConnected()
        await waitUntil { harness.controller.status == .connected }

        await harness.controller.disconnect(reason: "the controller disconnected")
        await waitUntil { harness.camera.activeSessionId == nil }

        XCTAssertNil(harness.camera.activeSessionId)
        XCTAssertEqual(harness.camera.status, .disconnected)
        XCTAssertTrue(harness.cameraPeer.isClosed)
    }

    /// Error case 6: the camera leaves Camera Mode mid-session.
    func test_theControllerIsToldWhenTheCameraLeaves() async throws {
        let harness = SignalingHarness()
        await harness.negotiate()
        harness.cameraPeer.simulateConnected()
        await waitUntil { harness.camera.status == .connected }

        await harness.camera.disconnect(reason: "the camera device left Camera Mode")
        await waitUntil { harness.controller.activeSessionId == nil }

        XCTAssertNil(harness.controller.activeSessionId)
        XCTAssertEqual(harness.controller.status, .disconnected)
    }

    func test_disconnectIsIdempotent() async throws {
        let harness = SignalingHarness()
        await harness.negotiate()

        await harness.controller.disconnect()
        await harness.controller.disconnect()

        let endings = harness.controllerEvents.filter { if case .ended = $0 { return true } else { return false } }
        XCTAssertEqual(endings.count, 1, "a second disconnect must not emit another ending")
    }

    /// Error case 8: stale sessions. With no backend to run a sweep, debris
    /// is cleared whenever a device starts a session.
    func test_expiredSessionsAreSweptWhenANewSessionStarts() async throws {
        let harness = SignalingHarness()
        let stale = WebRTCSessionRecord(
            sessionId: "stale-session",
            callerDeviceId: "device-gone",
            callerDeviceName: "Gone",
            calleeDeviceId: "device-camera",
            calleeDeviceName: "Kitchen iPhone",
            state: .offering,
            offer: SessionDescriptionPayload(kind: .offer, sdp: "old"),
            answer: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            expiresAt: Date(timeIntervalSince1970: 1)
        )
        try await harness.transport.createSession(stale)

        await harness.negotiate()

        XCTAssertFalse(
            harness.transport.storedSessions.contains { $0.sessionId == "stale-session" },
            "the expired session should have been swept"
        )
    }

    func test_anExpiredSessionIsNotAnswered() async throws {
        let harness = SignalingHarness()
        let expired = WebRTCSessionRecord(
            sessionId: "expired-session",
            callerDeviceId: "device-controller",
            callerDeviceName: "Pocket iPhone",
            calleeDeviceId: "device-camera",
            calleeDeviceName: "Kitchen iPhone",
            state: .offering,
            offer: SessionDescriptionPayload(kind: .offer, sdp: "old-offer"),
            answer: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            expiresAt: Date(timeIntervalSince1970: 1)
        )
        try await harness.transport.createSession(expired)

        harness.camera.startListeningForIncomingSessions()
        await waitUntil { harness.transport.storedSessions.isEmpty }

        XCTAssertNil(harness.camera.activeSessionId)
        XCTAssertTrue(harness.cameraPeer.remoteDescriptions.isEmpty)
    }

    func test_isExpired_comparesAgainstTheGivenTime() {
        let session = WebRTCSessionRecord(
            sessionId: "s",
            callerDeviceId: "a",
            callerDeviceName: "A",
            calleeDeviceId: "b",
            calleeDeviceName: "B",
            state: .offering,
            offer: nil,
            answer: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            expiresAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertFalse(session.isExpired(now: Date(timeIntervalSince1970: 99)))
        XCTAssertTrue(session.isExpired(now: Date(timeIntervalSince1970: 100)))
    }

    // MARK: - Authorization and self-connection

    func test_aDeviceRefusesToConnectToItself() async {
        let harness = SignalingHarness()

        await harness.controller.connect(
            toCameraDeviceId: harness.controllerIdentity.deviceId,
            cameraDeviceName: "Itself"
        )

        XCTAssertTrue(harness.transport.storedSessions.isEmpty, "no session should have been created")
        XCTAssertEqual(harness.controllerFailures(), [.sessionNotAddressedToThisDevice])
    }

    func test_aCameraIgnoresASessionItCreatedItself() async throws {
        let harness = SignalingHarness()
        // Both ends naming the camera - only reachable if a device is
        // registered in both roles and somehow picks itself.
        let selfSession = WebRTCSessionRecord(
            sessionId: "self-session",
            callerDeviceId: "device-camera",
            callerDeviceName: "Kitchen iPhone",
            calleeDeviceId: "device-camera",
            calleeDeviceName: "Kitchen iPhone",
            state: .offering,
            offer: SessionDescriptionPayload(kind: .offer, sdp: "self-offer"),
            answer: nil,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(WebRTCSessionRecord.timeToLive)
        )
        try await harness.transport.createSession(selfSession)

        harness.camera.startListeningForIncomingSessions()
        _ = await waitUntil(timeout: .milliseconds(300)) { harness.camera.activeSessionId != nil }

        XCTAssertNil(harness.camera.activeSessionId, "a device must never answer its own offer")
        XCTAssertTrue(harness.cameraPeer.remoteDescriptions.isEmpty)
    }

    func test_roleForDeviceId_identifiesNeitherEndForAnUnrelatedDevice() {
        let session = WebRTCSessionRecord(
            sessionId: "s",
            callerDeviceId: "a",
            callerDeviceName: "A",
            calleeDeviceId: "b",
            calleeDeviceName: "B",
            state: .offering,
            offer: nil,
            answer: nil,
            createdAt: Date(),
            expiresAt: Date()
        )

        XCTAssertEqual(session.role(for: "a"), .caller)
        XCTAssertEqual(session.role(for: "b"), .callee)
        XCTAssertNil(session.role(for: "c"), "a session must be rejectable per device, not just per account")
    }

    func test_aBusyCameraIgnoresASecondIncomingSession() async throws {
        let harness = SignalingHarness()
        await harness.negotiate()
        let firstSessionId = harness.camera.activeSessionId

        let second = WebRTCSessionRecord(
            sessionId: "second-session",
            callerDeviceId: "device-other-controller",
            callerDeviceName: "Another iPhone",
            calleeDeviceId: "device-camera",
            calleeDeviceName: "Kitchen iPhone",
            state: .offering,
            offer: SessionDescriptionPayload(kind: .offer, sdp: "second-offer"),
            answer: nil,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(WebRTCSessionRecord.timeToLive)
        )
        try await harness.transport.createSession(second)
        _ = await waitUntil(timeout: .milliseconds(300)) {
            harness.camera.activeSessionId == "second-session"
        }

        XCTAssertEqual(harness.camera.activeSessionId, firstSessionId, "the live session must not be dropped")
    }

    // MARK: - ICE failure and media honesty

    /// Error case 4: ICE cannot find a path. The message has to name the
    /// likely cause rather than just saying it failed.
    func test_iceFailure_marksTheSessionFailedAndExplainsTurn() async throws {
        let harness = SignalingHarness()
        await harness.negotiate()

        harness.controllerPeer.simulate(connectionState: .failed)
        // The session document is written from a detached task, so wait on it
        // rather than on the locally-updated status.
        await waitUntil { harness.storedSession?.state == .failed }

        XCTAssertEqual(harness.controller.status, .failed)
        XCTAssertEqual(harness.storedSession?.state, .failed)

        let failure = try XCTUnwrap(harness.controllerFailures().last)
        guard case .iceNegotiationFailed(let turnConfigured) = failure else {
            return XCTFail("expected an ICE failure, got \(failure)")
        }
        XCTAssertFalse(turnConfigured, "no TURN server is configured in tests")
        XCTAssertTrue(failure.message.contains("TURN"), "the message should explain the TURN limitation")
    }

    /// Error case 5: Wi-Fi drops. `disconnected` is recoverable, so it maps
    /// to Reconnecting rather than Failed.
    func test_aDroppedConnectionReportsReconnectingNotFailed() async throws {
        let harness = SignalingHarness()
        await harness.negotiate()
        harness.controllerPeer.simulateConnected()
        await waitUntil { harness.controller.status == .connected }

        harness.controllerPeer.simulate(connectionState: .disconnected)
        await waitUntil { harness.controller.status == .reconnecting }

        XCTAssertEqual(harness.controller.status, .reconnecting)
        XCTAssertEqual(harness.controllerFailures().last, .connectionLost)
        XCTAssertNotEqual(harness.storedSession?.state, .failed, "a recoverable drop must not fail the session")
    }

    func test_videoIsOnlyConfirmedWhenAFrameIsActuallyRendered() async throws {
        let harness = SignalingHarness()
        await harness.negotiate()

        harness.controllerPeer.simulateConnected()
        harness.controllerPeer.simulateRemoteVideoTrackAdded()
        await waitUntil { harness.controller.status == .connected }

        XCTAssertFalse(
            harness.controllerEvents.contains { if case .videoConfirmed = $0 { return true } else { return false } },
            "a negotiated track is not a received frame"
        )

        harness.controllerPeer.simulateFirstFrameRendered()
        await waitUntil {
            harness.controllerEvents.contains { if case .videoConfirmed = $0 { return true } else { return false } }
        }

        XCTAssertTrue(
            harness.controllerEvents.contains { if case .videoConfirmed = $0 { return true } else { return false } }
        )
    }

    /// The honesty requirement: ICE connected but no frames must be reported
    /// as a failure, not as a working connection.
    func test_connectedWithNoVideo_reportsMediaNeverArrived() async throws {
        let harness = SignalingHarness(mediaGracePeriod: .milliseconds(80))
        await harness.negotiate()

        harness.controllerPeer.simulateConnected()
        await waitUntil { harness.controllerFailures().contains(.mediaNeverArrived) }

        XCTAssertTrue(harness.controllerFailures().contains(.mediaNeverArrived))
    }

    func test_videoArrivingInTime_cancelsTheMediaWatchdog() async throws {
        let harness = SignalingHarness(mediaGracePeriod: .milliseconds(80))
        await harness.negotiate()

        harness.controllerPeer.simulateConnected()
        harness.controllerPeer.simulateFirstFrameRendered()
        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertFalse(
            harness.controllerFailures().contains(.mediaNeverArrived),
            "the watchdog must not fire once a frame has arrived"
        )
    }

    /// The camera is send-only, so it must not accuse itself of not
    /// receiving video.
    func test_theCameraDoesNotRunTheMediaWatchdog() async throws {
        let harness = SignalingHarness(mediaGracePeriod: .milliseconds(80))
        await harness.negotiate()

        harness.cameraPeer.simulateConnected()
        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertFalse(harness.cameraFailures().contains(.mediaNeverArrived))
    }

    // MARK: - Data channel over a negotiated session

    func test_controlMessagesFlowBothWaysOnceConnected() async throws {
        let harness = SignalingHarness()
        await harness.negotiate()
        harness.controllerPeer.simulateConnected()
        await waitUntil { harness.controller.status == .connected }

        try harness.controller.send(.capturePhoto(requestId: "req-1"))
        try harness.camera.send(.captureStarted(requestId: "req-1"))

        XCTAssertEqual(harness.cameraControlMessages(), [.capturePhoto(requestId: "req-1")])
        XCTAssertEqual(harness.controllerControlMessages(), [.captureStarted(requestId: "req-1")])
    }

    func test_pingIsAnsweredWithPong() async throws {
        let harness = SignalingHarness()
        await harness.negotiate()
        harness.controllerPeer.simulateConnected()
        await waitUntil { harness.controller.status == .connected }

        try harness.controller.send(.ping)
        XCTAssertEqual(harness.cameraControlMessages(), [.ping])

        // The camera's view model is what replies in the app; here the reply
        // is sent explicitly to verify it reaches the controller.
        try harness.camera.send(.pong)
        XCTAssertEqual(harness.controllerControlMessages(), [.pong])
    }

    func test_sendingBeforeTheChannelIsOpenThrows() async throws {
        let harness = SignalingHarness()
        await harness.negotiate()

        XCTAssertThrowsError(try harness.controller.send(.ping)) { error in
            guard case .snapshotTransferFailed = error as? RemoteCameraError else {
                return XCTFail("expected a transfer failure, got \(error)")
            }
        }
    }

    func test_aSessionEndFrameTearsTheSessionDownWithoutSurfacingAsAMessage() async throws {
        let harness = SignalingHarness()
        await harness.negotiate()
        harness.controllerPeer.simulateConnected()
        await waitUntil { harness.controller.status == .connected }

        try harness.camera.send(.sessionEnd(reason: "the camera device left Camera Mode"))
        await waitUntil { harness.controller.activeSessionId == nil }

        XCTAssertNil(harness.controller.activeSessionId)
        XCTAssertFalse(
            harness.controllerControlMessages().contains { if case .sessionEnd = $0 { return true } else { return false } },
            "session_end is lifecycle, not an application message"
        )
    }

    /// A malformed frame is logged and dropped. It must not tear the channel
    /// down, or a peer on a different build could break this one.
    func test_aMalformedControlFrameDoesNotEndTheSession() async throws {
        let harness = SignalingHarness()
        await harness.negotiate()
        harness.controllerPeer.simulateConnected()
        await waitUntil { harness.controller.status == .connected }

        harness.controllerPeer.simulateMalformedControlMessage()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertNotNil(harness.controller.activeSessionId)
        XCTAssertEqual(harness.controller.status, .connected)
    }

    // MARK: - Image transfer over a negotiated session

    /// Test E, over the session rather than in isolation: the camera chunks a
    /// payload, the controller reassembles it.
    func test_anImagePayloadCrossesTheSessionAndReassembles() async throws {
        let harness = SignalingHarness()
        await harness.negotiate()
        harness.cameraPeer.simulateConnected()
        await waitUntil { harness.camera.status == .connected }

        let payload = Data((0..<30_000).map { UInt8($0 % 253) })
        let transferId = UUID()
        let frames = try ImageTransferFrame.chunk(payload: payload, transferId: transferId)

        try harness.camera.send(.captureCompleted(
            requestId: "req-1",
            transferId: transferId.uuidString,
            byteCount: payload.count,
            chunkCount: frames.count
        ))
        try await harness.camera.sendImage(frames: frames)

        XCTAssertEqual(harness.controllerBinaryFrames().count, frames.count)

        let assembler = ImageTransferAssembler()
        var reassembled: Data?
        for frame in harness.controllerBinaryFrames() {
            if case .completed(_, let data) = assembler.accept(frame: frame) {
                reassembled = data
            }
        }
        XCTAssertEqual(reassembled, payload)
    }

    // MARK: - Signaling unavailable

    /// Error case: Firestore rejects the signaling writes, which is exactly
    /// what happens before the security rules are deployed.
    ///
    /// The error is built the way production builds it - through
    /// `FirestoreFailure` - so this also checks that a denial reaching the
    /// coordinator still carries the deployment guidance by the time it is
    /// shown. The mapping itself is covered by `FirestoreDiagnosticsTests`.
    func test_signalingFailure_isReportedWithDeploymentGuidance() async throws {
        let harness = SignalingHarness()
        let denial = NSError(
            domain: FirestoreErrorDomain,
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Missing or insufficient permissions."]
        )
        harness.transport.failureToThrow = FirestoreFailure.from(
            denial,
            operation: .create,
            path: "users/alice/webrtcSessions/session-1",
            uid: "alice"
        ).remoteCameraError

        await harness.controller.connect(toCameraDeviceId: "device-camera", cameraDeviceName: "Kitchen iPhone")
        await waitUntil { !harness.controllerFailures().isEmpty }

        let failure = try XCTUnwrap(harness.controllerFailures().first)
        guard case .signalingUnavailable = failure else {
            return XCTFail("expected a signaling failure, got \(failure)")
        }
        XCTAssertTrue(failure.message.contains("webrtcSessions"), "the message should name the collection to allow")
        XCTAssertTrue(failure.message.contains("denied"), "the message should say it was denied")
        XCTAssertEqual(harness.controller.status, .failed)
    }

    func test_payloadEncodingRoundTripsThroughTheFirestoreShape() throws {
        let offer = SessionDescriptionPayload(kind: .offer, sdp: "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\n")
        let candidate = IceCandidatePayload(
            candidate: "candidate:1 1 udp 2130706431 192.168.1.9 50000 typ host",
            sdpMid: "0",
            sdpMLineIndex: 0
        )

        XCTAssertEqual(SessionDescriptionPayload.decode(offer.encoded), offer)
        XCTAssertEqual(IceCandidatePayload.decode(candidate.encoded), candidate)
    }

    func test_payloadDecoding_rejectsIncompleteDocuments() {
        XCTAssertNil(SessionDescriptionPayload.decode(nil))
        XCTAssertNil(SessionDescriptionPayload.decode(["type": "offer"]))
        XCTAssertNil(SessionDescriptionPayload.decode(["type": "offer", "sdp": ""]))
        XCTAssertNil(SessionDescriptionPayload.decode(["type": "rollback", "sdp": "x"]))
        XCTAssertNil(IceCandidatePayload.decode(["sdpMLineIndex": 0]))
        XCTAssertNil(IceCandidatePayload.decode(["candidate": "c"]))
    }

    func test_sessionRecordDecoding_readsASessionDocument() throws {
        let created = Date(timeIntervalSince1970: 1_000)
        let session = try XCTUnwrap(WebRTCSessionRecord.decode(id: "session-1", data: [
            "callerDeviceId": "device-controller",
            "callerDeviceName": "Pocket iPhone",
            "calleeDeviceId": "device-camera",
            "calleeDeviceName": "Kitchen iPhone",
            "state": "offering",
            "offer": ["type": "offer", "sdp": "v=0"],
            "createdAt": created,
            "expiresAt": created.addingTimeInterval(120),
        ]))

        XCTAssertEqual(session.state, .offering)
        XCTAssertEqual(session.offer?.sdp, "v=0")
        XCTAssertNil(session.answer)
        XCTAssertEqual(session.peerDeviceName(from: .caller), "Kitchen iPhone")
        XCTAssertEqual(session.peerDeviceId(from: .callee), "device-controller")
    }

    func test_sessionRecordDecoding_rejectsAnUnknownState() {
        XCTAssertNil(WebRTCSessionRecord.decode(id: "s", data: [
            "callerDeviceId": "a",
            "calleeDeviceId": "b",
            "state": "vibing",
        ]))
    }

    func test_candidateCollectionNamesAreDistinctPerRole() {
        XCTAssertEqual(SignalingRole.caller.candidateCollectionName, "callerCandidates")
        XCTAssertEqual(SignalingRole.callee.candidateCollectionName, "calleeCandidates")
        XCTAssertEqual(SignalingRole.caller.other, .callee)
        XCTAssertEqual(SignalingRole.callee.other, .caller)
    }
}
