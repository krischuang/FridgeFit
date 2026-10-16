//
//  SignalingHarness.swift
//  FridgeFitTests
//

import Foundation
import XCTest
@testable import FridgeFit

/// Two `WebRTCSessionCoordinator`s - a controller and a camera - sharing one
/// `InMemorySignalingTransport`, with their mock peer connections linked.
///
/// This is what makes the negotiation testable end to end: a real
/// offer/answer/ICE exchange and a real data channel, with no Firebase, no
/// WebRTC framework, no camera and no network.
@MainActor
final class SignalingHarness {
    let transport = InMemorySignalingTransport()
    let controllerIdentity: DeviceIdentity
    let cameraIdentity: DeviceIdentity

    let controller: WebRTCSessionCoordinator
    let camera: WebRTCSessionCoordinator
    let controllerPeer: MockPeerConnection
    let cameraPeer: MockPeerConnection

    private(set) var controllerEvents: [WebRTCSessionCoordinator.Event] = []
    private(set) var cameraEvents: [WebRTCSessionCoordinator.Event] = []

    init(
        controllerName: String = "Pocket iPhone",
        cameraName: String = "Kitchen iPhone",
        mediaGracePeriod: Duration = .seconds(30)
    ) {
        controllerIdentity = DeviceIdentity(deviceId: "device-controller", deviceName: controllerName)
        cameraIdentity = DeviceIdentity(deviceId: "device-camera", deviceName: cameraName)

        controllerPeer = MockPeerConnection(identifier: "controller")
        cameraPeer = MockPeerConnection(identifier: "camera")
        MockPeerConnection.link(controllerPeer, cameraPeer)

        let controllerPeerRef = controllerPeer
        let cameraPeerRef = cameraPeer

        controller = WebRTCSessionCoordinator(
            identity: controllerIdentity,
            role: .caller,
            transport: transport,
            makePeerConnection: { controllerPeerRef },
            mediaGracePeriod: mediaGracePeriod
        )
        camera = WebRTCSessionCoordinator(
            identity: cameraIdentity,
            role: .callee,
            transport: transport,
            makePeerConnection: { cameraPeerRef },
            mediaGracePeriod: mediaGracePeriod
        )

        controller.setEventHandler { [weak self] event in
            self?.controllerEvents.append(event)
        }
        camera.setEventHandler { [weak self] event in
            self?.cameraEvents.append(event)
        }
    }

    /// Runs a full negotiation: camera starts listening, controller offers,
    /// camera answers, both sides apply each other's ICE candidates.
    ///
    /// - Returns: the session ID, or `nil` if negotiation didn't complete.
    @discardableResult
    func negotiate() async -> String? {
        camera.startListeningForIncomingSessions()
        await controller.connect(
            toCameraDeviceId: cameraIdentity.deviceId,
            cameraDeviceName: cameraIdentity.deviceName
        )
        // Negotiation completes when both sides hold the other's description.
        _ = await waitUntil {
            !self.controllerPeer.remoteDescriptions.isEmpty && !self.cameraPeer.remoteDescriptions.isEmpty
        }
        return controller.activeSessionId
    }

    var storedSession: WebRTCSessionRecord? {
        transport.storedSessions.first
    }

    func controllerFailures() -> [RemoteCameraError] {
        controllerEvents.compactMap { if case .failed(let error) = $0 { return error } else { return nil } }
    }

    func cameraFailures() -> [RemoteCameraError] {
        cameraEvents.compactMap { if case .failed(let error) = $0 { return error } else { return nil } }
    }

    func controllerStatuses() -> [DeviceConnectionStatus] {
        controllerEvents.compactMap { if case .statusChanged(let status) = $0 { return status } else { return nil } }
    }

    func cameraControlMessages() -> [RemoteControlMessage] {
        cameraEvents.compactMap { if case .controlMessage(let message) = $0 { return message } else { return nil } }
    }

    func controllerControlMessages() -> [RemoteControlMessage] {
        controllerEvents.compactMap { if case .controlMessage(let message) = $0 { return message } else { return nil } }
    }

    func controllerBinaryFrames() -> [Data] {
        controllerEvents.compactMap { if case .binaryFrame(let data) = $0 { return data } else { return nil } }
    }
}

/// Polls `condition` until it holds or the timeout expires.
///
/// Both signaling implementations deliver callbacks through a
/// `Task { @MainActor }` hop, so a negotiation step takes an unknown number
/// of main-actor turns. Polling is more robust than a fixed number of
/// `Task.yield()` calls and doesn't slow the suite down on success.
///
/// A free function rather than an `XCTestCase` extension so `SignalingHarness`
/// can use it too.
@MainActor
@discardableResult
func waitUntil(
    timeout: Duration = .seconds(3),
    _ condition: @MainActor () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(2))
    }
    return condition()
}
