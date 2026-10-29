//
//  PermissionRecoveryTests.swift
//  FridgeFitTests
//

@testable import FridgeFit
import UIKit
import XCTest

/// A denied camera permission has to lead somewhere.
///
/// Both camera entry points used to print the word "Settings" in a message
/// and leave the user to find it. These tests pin the two halves of the fix:
/// which states claim to be fixable in Settings, and that the destination is
/// a real URL rather than a string that silently fails to parse.
final class PermissionRecoveryTests: XCTestCase {

    // MARK: - Which states Settings can fix

    func test_deniedCameraAccessIsFixableInSettings() {
        XCTAssertTrue(CameraAccess.denied.isResolvableInSettings)
    }

    /// The Simulator, or an iPad without a camera. There is no switch to
    /// turn on, so offering the trip would waste it.
    func test_missingCameraIsNotFixableInSettings() {
        XCTAssertFalse(CameraAccess.unavailable.isResolvableInSettings)
    }

    func test_grantedAccessIsNotFixableInSettings() {
        XCTAssertFalse(CameraAccess.granted.isResolvableInSettings)
    }

    // MARK: - What the user is told

    func test_grantedAccessHasNothingToSay() {
        XCTAssertNil(CameraAccess.granted.prompt)
    }

    func test_deniedAccessOffersSettings() throws {
        let prompt = try XCTUnwrap(CameraAccess.denied.prompt)

        XCTAssertTrue(prompt.offersSettings)
        XCTAssertFalse(prompt.title.isEmpty)
        XCTAssertTrue(
            prompt.message.contains("Settings"),
            "The message should name where the user is being taken."
        )
    }

    /// Still explains itself, and still points at the photo library, but
    /// without a button that would lead nowhere.
    func test_unavailableCameraExplainsItselfWithoutOfferingSettings() throws {
        let prompt = try XCTUnwrap(CameraAccess.unavailable.prompt)

        XCTAssertFalse(prompt.offersSettings)
        XCTAssertTrue(prompt.message.contains("library"))
    }

    // MARK: - The destination

    func test_settingsDestinationIsAUsableURL() throws {
        let url = try XCTUnwrap(SystemSettings.appSettings)

        XCTAssertEqual(url.absoluteString, UIApplication.openSettingsURLString)
    }

    // MARK: - The remote-camera side

    func test_onlyTheDeniedPermissionSendsTheUserToSettings() {
        XCTAssertTrue(RemoteCameraError.cameraPermissionDenied.isResolvableInSettings)

        let notFixableInSettings: [RemoteCameraError] = [
            .cameraUnavailable,
            .notAuthenticated,
            .noCameraDevicesFound,
            .sessionExpired,
            .sessionNotAddressedToThisDevice,
            .connectionLost,
            .mediaNeverArrived,
            .iceNegotiationFailed(turnConfigured: false),
            .iceNegotiationFailed(turnConfigured: true),
            .peerLeft(deviceName: "Kitchen iPhone"),
            .snapshotTransferFailed(reason: "encode failed"),
            .signalingUnavailable(reason: "permission denied")
        ]
        for error in notFixableInSettings {
            XCTAssertFalse(
                error.isResolvableInSettings,
                "\(error) is not something iOS Settings can change."
            )
        }
    }

    /// The message and the affordance have to agree: a card that offers
    /// Settings must also say what to do once the user is there.
    func test_theDeniedPermissionMessageSaysWhatToTurnOn() {
        let message = RemoteCameraError.cameraPermissionDenied.message

        XCTAssertTrue(message.contains("Settings"))
        XCTAssertTrue(message.contains("Camera"))
    }

    /// `activate()` refuses on a device with no capture hardware, and because
    /// that is not a permission problem the card must not offer Settings.
    /// This is the path the Simulator always takes.
    @MainActor
    func test_activatingWithoutACameraReportsAnErrorThatSettingsCannotFix() async {
        let viewModel = CameraModeViewModel(
            identity: DeviceIdentity(deviceId: "test-device", deviceName: "Test iPhone"),
            registry: InMemoryDeviceRegistry(),
            transport: InMemorySignalingTransport()
        )

        await viewModel.activate()

        guard viewModel.errorMessage != nil else {
            // A machine that does have a capture device would get past the
            // guard. Nothing to assert about an error that never happened.
            return
        }
        XCTAssertFalse(viewModel.errorIsResolvableInSettings)
    }
}
