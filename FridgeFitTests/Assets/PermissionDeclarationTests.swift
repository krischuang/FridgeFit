//
//  PermissionDeclarationTests.swift
//  FridgeFitTests
//
//  Keeps `Info.plist` honest in both directions.
//
//  A **missing** usage string is a crash: iOS terminates an app that touches
//  a protected resource without one. An **unnecessary** usage string is an
//  App Review question the app cannot answer, and a prompt the user should
//  never have been shown. Neither is a compile error, so both are checked
//  here against what the code actually does.
//

import XCTest
@testable import FridgeFit

final class PermissionDeclarationTests: XCTestCase {

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        // .../FridgeFitTests/Assets/PermissionDeclarationTests.swift
        for _ in 0 ..< 3 { url.deleteLastPathComponent() }
        return url
    }

    private func infoPlist() throws -> [String: Any] {
        let url = Self.repositoryRoot.appendingPathComponent("FridgeFit/Info.plist")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    /// Every `*UsageDescription` currently declared.
    private func declaredUsageKeys() throws -> Set<String> {
        Set(try infoPlist().keys.filter { $0.hasSuffix("UsageDescription") })
    }

    // MARK: - Required and present

    /// `CameraPicker` calls `AVCaptureDevice.requestAccess(for: .video)`.
    func test_cameraUsageDescription_isDeclaredAndExplainsWhy() throws {
        let plist = try infoPlist()
        let description = try XCTUnwrap(
            plist["NSCameraUsageDescription"] as? String,
            "the app requests camera access, so this key is mandatory"
        )

        XCTAssertGreaterThan(description.count, 40, "a usage string must actually explain the use")
        XCTAssertTrue(description.lowercased().contains("camera"))
        // The camera is used for two distinct things; both should be named.
        XCTAssertTrue(description.lowercased().contains("fridge"))
        XCTAssertTrue(description.lowercased().contains("camera mode"))
    }

    /// The gap this test was written for.
    ///
    /// WebRTC gathers host (LAN) ICE candidates and, on the same Wi-Fi,
    /// connects straight to an address like 192.168.x.x. On iOS 14+ that is
    /// local network access and requires this key; without it the prompt
    /// appears with no explanation and App Review flags it.
    func test_localNetworkUsageDescription_isDeclaredForCameraMode() throws {
        let plist = try infoPlist()
        let description = try XCTUnwrap(
            plist["NSLocalNetworkUsageDescription"] as? String,
            """
            Camera Mode connects two iPhones over the local network via WebRTC \
            host candidates, which requires NSLocalNetworkUsageDescription on iOS 14+.
            """
        )

        XCTAssertGreaterThan(description.count, 40)
        XCTAssertTrue(description.lowercased().contains("camera mode"))
        XCTAssertTrue(
            description.lowercased().contains("never uploaded")
                || description.lowercased().contains("between your devices"),
            "the string should say the video does not go to FridgeFit"
        )
    }

    // MARK: - Deliberately absent

    /// The app streams **video only**: `WebRTCFactory` sets
    /// `useManualAudio = true` and `isAudioEnabled = false`, and no audio
    /// track is ever created. Declaring microphone access would request a
    /// permission the app never uses.
    func test_microphoneUsageDescription_isNotDeclared_becauseNoAudioIsCaptured() throws {
        XCTAssertNil(
            try infoPlist()["NSMicrophoneUsageDescription"],
            "no audio is captured, so this permission must not be requested"
        )

        let factory = try source("FridgeFit/Data/RemoteCamera/WebRTCFactory.swift")
        XCTAssertTrue(factory.contains("isAudioEnabled = false"), "audio is no longer disabled")

        // Nothing anywhere may ask for microphone access.
        for path in ["FridgeFit/Data/RemoteCamera/CameraVideoSource.swift",
                     "FridgeFit/Views/Scanner/CameraPicker.swift"] {
            XCTAssertFalse(
                try source(path).contains("AVMediaType.audio"),
                "\(path) captures audio but no usage string is declared"
            )
        }
    }

    /// `PhotosPicker` runs out of process and grants the app no library
    /// access, so iOS does not require this key and shows no prompt. Adding
    /// it would request access the app does not have and does not need.
    func test_photoLibraryUsageDescription_isNotDeclared_becausePhotosPickerNeedsNone() throws {
        XCTAssertNil(try infoPlist()["NSPhotoLibraryUsageDescription"])
        XCTAssertNil(try infoPlist()["NSPhotoLibraryAddUsageDescription"])
    }

    /// Nothing schedules a notification, so no authorization is requested.
    /// The Settings rows that advertised reminders were removed in the
    /// earlier hardening pass precisely because the feature does not exist.
    func test_noNotificationAuthorisationIsRequested() throws {
        for path in ["FridgeFit/FridgeFitApp.swift",
                     "FridgeFit/Views/Profile/ProfileSettingsView.swift"] {
            let swift = try source(path)
            XCTAssertFalse(swift.contains("UNUserNotificationCenter"), "\(path) requests notifications")
        }
    }

    /// The whole declared set, pinned. A new usage string appearing here
    /// without a matching code path - or a code path appearing without its
    /// string - should fail rather than ship.
    func test_theDeclaredPermissionSetIsExactlyWhatTheCodeUses() throws {
        XCTAssertEqual(
            try declaredUsageKeys(),
            ["NSCameraUsageDescription", "NSLocalNetworkUsageDescription"],
            """
            The declared permissions no longer match the code. Camera: \
            AVCaptureDevice.requestAccess(for: .video). Local network: WebRTC \
            host candidates on the same Wi-Fi. Anything else needs either a \
            code path or removal.
            """
        )
    }

    // MARK: - Bonjour

    /// `NSBonjourServices` is deliberately absent: the two devices find each
    /// other through Firestore signalling, not mDNS. Declaring a service
    /// type would claim discovery behaviour the app does not perform.
    func test_bonjourServicesAreNotDeclared_becauseNoServiceIsBrowsed() throws {
        XCTAssertNil(try infoPlist()["NSBonjourServices"])

        for path in ["FridgeFit/Data/RemoteCamera/WebRTCClient.swift",
                     "FridgeFit/Data/RemoteCamera/FirestoreSignalingTransport.swift"] {
            let swift = try source(path)
            XCTAssertFalse(swift.contains("NetService"), "\(path) browses Bonjour")
            XCTAssertFalse(swift.contains("NWBrowser"), "\(path) browses Bonjour")
        }
    }

    // MARK: - Denied-permission recovery

    /// A denied camera permission must land somewhere explained and
    /// recoverable rather than on a dead screen. The recovery UI exists and
    /// offers a route to Settings.
    func test_deniedCameraPermission_hasAnExplainedRecoveryPath() throws {
        let prompt = try source("FridgeFit/Views/Support/CameraAccessPrompt.swift")

        XCTAssertTrue(
            prompt.contains("UIApplication.openSettingsURLString"),
            "the denied-permission state must offer a way into Settings"
        )

        // Every `AVAuthorizationStatus` must be accounted for, including
        // `@unknown default` so a future status cannot fall through to a
        // black viewfinder. Checked by name rather than by exact `case`
        // spelling: the four are handled as `case .denied, .restricted:` on
        // one line, which a literal "case .restricted" search misses.
        let picker = try source("FridgeFit/Views/Scanner/CameraPicker.swift")
        for status in ["authorized", "notDetermined", "denied", "restricted"] {
            XCTAssertTrue(
                picker.contains(".\(status)"),
                "AVAuthorizationStatus.\(status) is not handled"
            )
        }
        XCTAssertTrue(picker.contains("@unknown default"), "a future status would fall through")
    }
}
