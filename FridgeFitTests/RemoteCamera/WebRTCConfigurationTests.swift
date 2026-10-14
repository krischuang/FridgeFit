//
//  WebRTCConfigurationTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// ICE server configuration, and the honesty of what it claims about
/// connectivity.
final class WebRTCConfigurationTests: XCTestCase {

    /// Stands in for Info.plist, so TURN configuration can be tested without
    /// touching build settings.
    private final class StubBundle: Bundle, @unchecked Sendable {
        private let values: [String: String]

        init(values: [String: String]) {
            self.values = values
            super.init()
        }

        override func object(forInfoDictionaryKey key: String) -> Any? {
            values[key]
        }
    }

    func test_stunIsConfiguredByDefault() {
        let configuration = WebRTCConfiguration.load(bundle: StubBundle(values: [:]))

        XCTAssertEqual(configuration.stunURLs, WebRTCConfiguration.defaultStunURLs)
        XCTAssertFalse(configuration.stunURLs.isEmpty)
        XCTAssertTrue(configuration.stunURLs.allSatisfy { $0.hasPrefix("stun:") })
    }

    func test_moreThanOneStunServerIsConfigured() {
        // One unreachable server shouldn't stall candidate gathering.
        XCTAssertGreaterThan(WebRTCConfiguration.defaultStunURLs.count, 1)
    }

    func test_turnIsAbsentWhenNotConfigured() {
        let configuration = WebRTCConfiguration.load(bundle: StubBundle(values: [:]))

        XCTAssertNil(configuration.turnServer)
        XCTAssertFalse(configuration.hasTurnServer)
    }

    func test_turnIsLoadedWhenAllThreeValuesArePresent() throws {
        let configuration = WebRTCConfiguration.load(bundle: StubBundle(values: [
            "TURN_URL": "turn:turn.example.com:3478",
            "TURN_USERNAME": "user",
            "TURN_CREDENTIAL": "secret",
        ]))

        let turn = try XCTUnwrap(configuration.turnServer)
        XCTAssertEqual(turn.url, "turn:turn.example.com:3478")
        XCTAssertTrue(configuration.hasTurnServer)
    }

    /// A half-configured TURN server gathers relay candidates that always
    /// fail authentication, which looks exactly like a network fault.
    func test_aPartiallyConfiguredTurnServerIsIgnored() {
        let missingCredential = WebRTCConfiguration.load(bundle: StubBundle(values: [
            "TURN_URL": "turn:turn.example.com:3478",
            "TURN_USERNAME": "user",
        ]))
        let missingUsername = WebRTCConfiguration.load(bundle: StubBundle(values: [
            "TURN_URL": "turn:turn.example.com:3478",
            "TURN_CREDENTIAL": "secret",
        ]))

        XCTAssertNil(missingCredential.turnServer)
        XCTAssertNil(missingUsername.turnServer)
    }

    /// Unset xcconfig variables come through Info.plist as the literal
    /// placeholder or an empty string, neither of which is a TURN server.
    func test_blankValuesAreTreatedAsUnconfigured() {
        let configuration = WebRTCConfiguration.load(bundle: StubBundle(values: [
            "TURN_URL": "   ",
            "TURN_USERNAME": "",
            "TURN_CREDENTIAL": "",
        ]))

        XCTAssertNil(configuration.turnServer)
    }

    // MARK: - What it tells the user

    func test_logDescriptionNeverIncludesTurnCredentials() {
        let configuration = WebRTCConfiguration.load(bundle: StubBundle(values: [
            "TURN_URL": "turn:turn.example.com:3478",
            "TURN_USERNAME": "user",
            "TURN_CREDENTIAL": "super-secret-password",
        ]))

        let logLine = configuration.describedForLogs
        XCTAssertFalse(logLine.contains("super-secret-password"))
        XCTAssertFalse(logLine.contains("user"))
        XCTAssertFalse(logLine.contains("turn.example.com"))
        XCTAssertTrue(logLine.contains("configured"))
    }

    /// STUN alone is not a connectivity guarantee, and the caveat shown to
    /// the user has to say so.
    func test_theStunOnlyCaveatWarnsAboutDifferentNetworks() {
        let configuration = WebRTCConfiguration.load(bundle: StubBundle(values: [:]))

        let caveat = configuration.connectivityCaveat
        XCTAssertTrue(caveat.contains("same Wi-Fi"))
        XCTAssertTrue(caveat.contains("may fail"))
    }

    func test_theTurnCaveatIsMorePositive() {
        let configuration = WebRTCConfiguration.load(bundle: StubBundle(values: [
            "TURN_URL": "turn:turn.example.com:3478",
            "TURN_USERNAME": "user",
            "TURN_CREDENTIAL": "secret",
        ]))

        XCTAssertTrue(configuration.connectivityCaveat.contains("TURN relay is configured"))
    }

    func test_iceFailureMessageDependsOnWhetherTurnWasConfigured() {
        let withoutTurn = RemoteCameraError.iceNegotiationFailed(turnConfigured: false)
        let withTurn = RemoteCameraError.iceNegotiationFailed(turnConfigured: true)

        XCTAssertTrue(withoutTurn.message.contains("STUN alone"))
        XCTAssertTrue(withoutTurn.message.contains("TURN"))
        XCTAssertTrue(withTurn.message.contains("TURN relay didn't work"))
        XCTAssertNotEqual(withoutTurn.message, withTurn.message)
    }

    // MARK: - Error surface

    func test_everyErrorHasANonEmptyMessage() {
        let errors: [RemoteCameraError] = [
            .noCameraDevicesFound,
            .notAuthenticated,
            .sessionNotAddressedToThisDevice,
            .sessionExpired,
            .cameraPermissionDenied,
            .cameraUnavailable,
            .iceNegotiationFailed(turnConfigured: false),
            .connectionLost,
            .peerLeft(deviceName: "Kitchen iPhone"),
            .mediaNeverArrived,
            .snapshotTransferFailed(reason: "test"),
            .signalingUnavailable(reason: "test"),
        ]

        for error in errors {
            XCTAssertFalse(error.message.isEmpty, "\(error) needs a message")
        }
    }

    func test_permissionAndHardwareFailuresAreNotRetryable() {
        XCTAssertFalse(RemoteCameraError.cameraPermissionDenied.isRecoverable)
        XCTAssertFalse(RemoteCameraError.cameraUnavailable.isRecoverable)
        XCTAssertFalse(RemoteCameraError.notAuthenticated.isRecoverable)
        XCTAssertTrue(RemoteCameraError.connectionLost.isRecoverable)
        XCTAssertTrue(RemoteCameraError.noCameraDevicesFound.isRecoverable)
    }

    /// Error case 3: camera permission denied. The message has to point at
    /// Settings, since nothing in the app can grant it.
    func test_permissionDeniedPointsAtSettings() {
        XCTAssertTrue(RemoteCameraError.cameraPermissionDenied.message.contains("Settings"))
    }

    /// The reason is surfaced verbatim rather than being wrapped in a fixed
    /// hint. `FirestoreFailure` builds the reason and is the thing that knows
    /// whether deploying rules is the right advice - see
    /// `FirestoreDiagnosticsTests`.
    func test_signalingUnavailableSurfacesTheReasonItWasGiven() {
        let message = RemoteCameraError.signalingUnavailable(
            reason: "the request to users/{uid}/devices was denied"
        ).message

        XCTAssertTrue(message.contains("users/{uid}/devices"))
        XCTAssertTrue(message.contains("denied"))
    }

    // MARK: - Status presentation

    func test_onlyConnectedCountsAsLive() {
        for status in DeviceConnectionStatus.allCases {
            XCTAssertEqual(status.isLive, status == .connected, "\(status)")
        }
    }

    func test_anInFlightSessionIsNotConnectable() {
        XCTAssertFalse(DeviceConnectionStatus.connecting.isConnectable)
        XCTAssertFalse(DeviceConnectionStatus.connected.isConnectable)
        XCTAssertFalse(DeviceConnectionStatus.reconnecting.isConnectable)
        XCTAssertFalse(DeviceConnectionStatus.offline.isConnectable)
        XCTAssertTrue(DeviceConnectionStatus.available.isConnectable)
        XCTAssertTrue(DeviceConnectionStatus.disconnected.isConnectable)
        XCTAssertTrue(DeviceConnectionStatus.failed.isConnectable)
    }

    func test_peerConnectionStateMapsToTheDisplayedStatus() {
        XCTAssertEqual(PeerConnectionState.connecting.deviceStatus, .connecting)
        XCTAssertEqual(PeerConnectionState.connected.deviceStatus, .connected)
        // A drop is recoverable, so it reads as Reconnecting, not Failed.
        XCTAssertEqual(PeerConnectionState.disconnected.deviceStatus, .reconnecting)
        XCTAssertEqual(PeerConnectionState.failed.deviceStatus, .failed)
        XCTAssertEqual(PeerConnectionState.closed.deviceStatus, .disconnected)
    }

    func test_everyStatusAndRoleHasADisplayName() {
        for status in DeviceConnectionStatus.allCases {
            XCTAssertFalse(status.displayName.isEmpty)
        }
        for role in DeviceRole.allCases {
            XCTAssertFalse(role.displayName.isEmpty)
        }
        XCTAssertEqual(DeviceRole.camera.other, .controller)
        XCTAssertEqual(DeviceRole.controller.other, .camera)
    }

    func test_cameraPositionFlips() {
        XCTAssertEqual(RemoteControlMessage.CameraPosition.front.other, .back)
        XCTAssertEqual(RemoteControlMessage.CameraPosition.back.other, .front)
        XCTAssertEqual(RemoteControlMessage.CameraPosition.back.displayName, "Rear")
    }
}
