//
//  RemoteCameraViewMountingTests.swift
//  FridgeFitTests
//

import SwiftUI
import UIKit
import XCTest
@testable import FridgeFit

/// Mounts each new screen in a real window and runs its lifecycle.
///
/// Everything else in this suite tests view models. This tests the *views*:
/// that each one builds its body without trapping, that its `@StateObject`
/// constructs, that `.task` runs and settles, and that tearing the screen
/// down releases cleanly. Those failures are invisible to a view-model test
/// and would otherwise only turn up by opening the app.
///
/// Deliberately does **not** screenshot the result. Capturing needs
/// `drawHierarchy(in:afterScreenUpdates:)`, which UIKit refuses to do
/// properly for a window outside a foreground scene ("Rendering a window
/// requires it to be in a foreground scene") and which corrupted process
/// state badly enough to abort the test runner when tried. Mounting is the
/// part with diagnostic value; the picture was only ever a convenience.
@MainActor
final class RemoteCameraViewMountingTests: XCTestCase {

    private let identity = DeviceIdentity(deviceId: "mount-device", deviceName: "Mount iPhone")
    private var window: UIWindow?
    private var retainedAuthViewModel: AuthViewModel?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil

        // Let SwiftUI detach the hosted hierarchy before releasing dependencies
        // that were also retained by its environment.
        await Task.yield()
        retainedAuthViewModel = nil

        // A turn for the hosting view's teardown to finish before the next test.
        try? await Task.sleep(for: .milliseconds(50))
        try await super.tearDown()
    }

    private func seededRegistry() -> InMemoryDeviceRegistry {
        InMemoryDeviceRegistry(seedDevices: [
            identity.asRegisteredDevice(role: .controller),
            RegisteredDevice(
                deviceId: "kitchen-device",
                deviceName: "Kitchen iPhone",
                deviceRole: .camera,
                connectionStatus: .available,
                lastSeenAt: Date(),
                createdAt: Date()
            ),
        ])
    }

    /// Hosts `view`, lays it out, and lets `.task` run to completion.
    private func mount<V: View>(_ view: V) async {
        let bounds = CGRect(x: 0, y: 0, width: 393, height: 852)
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window

        host.view.frame = bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // Enough turns for `.task` and the registry's `Task { @MainActor }`
        // callbacks to land, and for `List` to build its rows.
        for _ in 0..<3 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(120))
        }
        host.view.layoutIfNeeded()
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if condition() { return true }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }

        return condition()
    }

    func test_connectedDevicesViewMountsAndDiscoversTheCamera() async {
        let viewModel = ConnectedDevicesViewModel(identity: identity, registry: seededRegistry())

        await mount(NavigationStack { ConnectedDevicesView(viewModel: viewModel) })

        // Proves `.task` actually ran, not just that the body compiled.
        XCTAssertEqual(viewModel.availableCameras.map(\.deviceName), ["Kitchen iPhone"])
        XCTAssertNil(viewModel.errorMessage)
        viewModel.stop()
    }

    /// In the Simulator there is no capture device, so Camera Mode must
    /// explain itself rather than sit on a black preview.
    func test_cameraModeViewMountsAndReportsNoCamera() async {
        let viewModel = CameraModeViewModel(
            identity: identity,
            registry: InMemoryDeviceRegistry(),
            transport: InMemorySignalingTransport()
        )

        await mount(NavigationStack { CameraModeView(viewModel: viewModel) })

        XCTAssertFalse(viewModel.isActive)
        XCTAssertFalse(viewModel.isReceivingFrames)
        XCTAssertEqual(viewModel.errorMessage, RemoteCameraError.cameraUnavailable.message)
        await viewModel.deactivate()
    }

    func test_remoteCameraViewMountsAndListsCameras() async {
        let viewModel = RemoteCameraViewModel(
            identity: identity,
            registry: seededRegistry(),
            transport: InMemorySignalingTransport()
        )

        await mount(NavigationStack { RemoteCameraView(viewModel: viewModel) })

        XCTAssertEqual(viewModel.availableCameras.map(\.deviceName), ["Kitchen iPhone"])
        XCTAssertFalse(viewModel.isConnected)
        XCTAssertNotNil(
            viewModel.recognitionUnavailableExplanation,
            "the default recognition service should explain that it isn't implemented"
        )
        await viewModel.stop()
    }

    /// The snapshot branch of the body - captured image, share sheet, and the
    /// mock-data badge - which the empty state never builds.
    func test_remoteCameraViewMountsWithASnapshotAndMockRecognition() async {
        let viewModel = RemoteCameraViewModel(
            identity: identity,
            registry: seededRegistry(),
            transport: InMemorySignalingTransport(),
            recognitionService: MockFoodRecognitionService()
        )
        await viewModel.start()
        viewModel.presentSnapshotForPreview(TestImage.makeUIImage(size: CGSize(width: 600, height: 450)))
        await viewModel.recognizeSnapshot()

        await mount(NavigationStack { RemoteCameraView(viewModel: viewModel) })

        XCTAssertNotNil(viewModel.snapshot)
        XCTAssertEqual(viewModel.recognition?.isMockData, true)
        await viewModel.stop()
    }

    func test_profileViewMountsWithTheConnectedDevicesLink() async {
        let seededEvent = InventoryEvent(
            pantryItemID: UUID(),
            itemName: "Mount-test spinach",
            kind: .finished
        )
        let inventory = InventoryStore(
            pantryRepository: InMemoryPantryRepository(),
            eventRepository: InMemoryInventoryEventRepository(seedEvents: [seededEvent])
        )
        let authViewModel = AuthViewModel(observesAuthState: false)
        retainedAuthViewModel = authViewModel

        await mount(
            NavigationStack {
                ProfileView(inventory: inventory, onFindRecipes: {})
                    .environmentObject(authViewModel)
                    .environment(\.pantryRepository, InMemoryPantryRepository())
            }
        )

        let didLoadSeededEvent = await waitUntil {
            inventory.events.contains(seededEvent)
        }

        XCTAssertTrue(didLoadSeededEvent, "ProfileView did not finish loading its seeded inventory event")
        XCTAssertEqual(inventory.events, [seededEvent])
        // Reaching here also means the Profile entry point and its lazily-built
        // Connected Devices link rendered without accessing Firebase Auth.
        XCTAssertNotNil(window?.rootViewController)
    }
}
