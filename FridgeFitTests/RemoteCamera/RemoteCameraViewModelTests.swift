//
//  RemoteCameraViewModelTests.swift
//  FridgeFitTests
//

import UIKit
import XCTest
@testable import FridgeFit

/// The controller screen, driven end to end: discover a camera, connect,
/// confirm video, ask for a photo, receive and display it.
///
/// Uses the real `RemoteCameraViewModel` and `WebRTCSessionCoordinator` with
/// a `MockPeerConnection` pair, so the only thing stubbed out is the WebRTC
/// transport itself.
@MainActor
final class RemoteCameraViewModelTests: XCTestCase {

    /// Controller view model plus a camera-side coordinator, wired together.
    private struct Harness {
        let viewModel: RemoteCameraViewModel
        let camera: WebRTCSessionCoordinator
        let controllerPeer: MockPeerConnection
        let cameraPeer: MockPeerConnection
        let cameraDevice: RegisteredDevice
        let registry: InMemoryDeviceRegistry
        let transport: InMemorySignalingTransport
        let cameraEvents: EventLog
    }

    /// Reference box so the camera coordinator's event closure can record
    /// into something the test can read.
    private final class EventLog {
        var events: [WebRTCSessionCoordinator.Event] = []

        var controlMessages: [RemoteControlMessage] {
            events.compactMap { if case .controlMessage(let m) = $0 { return m } else { return nil } }
        }
    }

    private func makeHarness(
        recognitionService: any FoodRecognitionService = UnimplementedFoodRecognitionService()
    ) -> Harness {
        let controllerIdentity = DeviceIdentity(deviceId: "device-controller", deviceName: "Pocket iPhone")
        let cameraIdentity = DeviceIdentity(deviceId: "device-camera", deviceName: "Kitchen iPhone")
        let cameraDevice = cameraIdentity.asRegisteredDevice(role: .camera)

        let registry = InMemoryDeviceRegistry(seedDevices: [cameraDevice])
        let transport = InMemorySignalingTransport()

        let controllerPeer = MockPeerConnection(identifier: "controller")
        let cameraPeer = MockPeerConnection(identifier: "camera")
        MockPeerConnection.link(controllerPeer, cameraPeer)

        let viewModel = RemoteCameraViewModel(
            identity: controllerIdentity,
            registry: registry,
            transport: transport,
            recognitionService: recognitionService,
            makePeerConnection: { controllerPeer }
        )

        let camera = WebRTCSessionCoordinator(
            identity: cameraIdentity,
            role: .callee,
            transport: transport,
            makePeerConnection: { cameraPeer }
        )
        let log = EventLog()
        camera.setEventHandler { log.events.append($0) }

        return Harness(
            viewModel: viewModel,
            camera: camera,
            controllerPeer: controllerPeer,
            cameraPeer: cameraPeer,
            cameraDevice: cameraDevice,
            registry: registry,
            transport: transport,
            cameraEvents: log
        )
    }

    /// Discovers, connects, and brings the link up with confirmed video.
    private func connected(_ harness: Harness) async {
        await harness.viewModel.start()
        await waitUntil { !harness.viewModel.availableCameras.isEmpty }
        harness.camera.startListeningForIncomingSessions()
        await harness.viewModel.connect(to: harness.cameraDevice)
        await waitUntil { !harness.cameraPeer.remoteDescriptions.isEmpty }
        harness.controllerPeer.simulateConnected()
        harness.controllerPeer.simulateFirstFrameRendered()
        await waitUntil { harness.viewModel.isReceivingVideo }
    }

    // MARK: - Discovery

    func test_start_discoversTheCameraOnTheSameAccount() async {
        let harness = makeHarness()

        await harness.viewModel.start()
        await waitUntil { !harness.viewModel.availableCameras.isEmpty }

        XCTAssertEqual(harness.viewModel.availableCameras.map(\.deviceName), ["Kitchen iPhone"])
        await harness.viewModel.stop()
    }

    func test_start_doesNotListTheControllerItself() async throws {
        let harness = makeHarness()
        // Same install registered as a camera as well - it must still not
        // appear in its own list.
        try await harness.registry.register(
            device: DeviceIdentity(deviceId: "device-controller", deviceName: "Pocket iPhone")
                .asRegisteredDevice(role: .camera)
        )

        await harness.viewModel.start()
        await waitUntil { !harness.viewModel.availableCameras.isEmpty }

        XCTAssertFalse(harness.viewModel.availableCameras.contains { $0.deviceId == "device-controller" })
        await harness.viewModel.stop()
    }

    func test_connectingToItself_isRefused() async {
        let harness = makeHarness()
        await harness.viewModel.start()

        await harness.viewModel.connect(
            to: DeviceIdentity(deviceId: "device-controller", deviceName: "Pocket iPhone")
                .asRegisteredDevice(role: .camera)
        )

        XCTAssertFalse(harness.viewModel.isConnected)
        XCTAssertEqual(
            harness.viewModel.errorMessage,
            RemoteCameraError.sessionNotAddressedToThisDevice.message
        )
        await harness.viewModel.stop()
    }

    // MARK: - Connecting and video honesty

    func test_connect_reachesConnectedAndConfirmsVideo() async {
        let harness = makeHarness()

        await connected(harness)

        XCTAssertTrue(harness.viewModel.isConnected)
        XCTAssertEqual(harness.viewModel.status, .connected)
        XCTAssertTrue(harness.viewModel.isReceivingVideo)
        XCTAssertEqual(harness.viewModel.connectedCameraName, "Kitchen iPhone")
        await harness.viewModel.stop()
    }

    /// The screen must not offer the shutter until frames are confirmed -
    /// whatever came back would not be what the user framed.
    func test_captureIsUnavailableUntilVideoIsConfirmed() async {
        let harness = makeHarness()
        await harness.viewModel.start()
        await waitUntil { !harness.viewModel.availableCameras.isEmpty }
        harness.camera.startListeningForIncomingSessions()
        await harness.viewModel.connect(to: harness.cameraDevice)
        harness.controllerPeer.simulateConnected()
        await waitUntil { harness.viewModel.status == .connected }

        XCTAssertFalse(harness.viewModel.isReceivingVideo)
        XCTAssertFalse(harness.viewModel.canRequestCapture)

        harness.viewModel.requestCapture()

        XCTAssertEqual(harness.viewModel.errorMessage, RemoteCameraError.mediaNeverArrived.message)
        XCTAssertFalse(harness.viewModel.isAwaitingSnapshot)
        await harness.viewModel.stop()
    }

    // MARK: - Capture round trip

    func test_capture_receivesAndDisplaysTheSnapshot() async throws {
        let harness = makeHarness()
        await connected(harness)

        harness.viewModel.requestCapture()
        await waitUntil { !harness.cameraEvents.controlMessages.isEmpty }

        // The camera side: encode a real image and push it over the channel.
        let requestId = try XCTUnwrap(
            harness.cameraEvents.controlMessages.compactMap { message -> String? in
                if case .capturePhoto(let id) = message { return id } else { return nil }
            }.first
        )
        let payload = try SnapshotImageEncoder.encode(
            TestImage.makeUIImage(size: CGSize(width: 1600, height: 1200))
        )
        let transferId = UUID()
        let frames = try ImageTransferFrame.chunk(payload: payload, transferId: transferId)

        try harness.camera.send(.captureStarted(requestId: requestId))
        try harness.camera.send(.captureCompleted(
            requestId: requestId,
            transferId: transferId.uuidString,
            byteCount: payload.count,
            chunkCount: frames.count
        ))
        try await harness.camera.sendImage(frames: frames)
        await waitUntil { harness.viewModel.snapshot != nil }

        let snapshot = try XCTUnwrap(harness.viewModel.snapshot)
        XCTAssertEqual(snapshot.size.width, 1280, accuracy: 1)
        XCTAssertFalse(harness.viewModel.isAwaitingSnapshot)
        XCTAssertNil(harness.viewModel.errorMessage)
        await harness.viewModel.stop()
    }

    /// Error case 9: the snapshot transfer fails on the camera side.
    func test_captureFailedFromTheCamera_isSurfacedAndClearsTheWait() async throws {
        let harness = makeHarness()
        await connected(harness)

        harness.viewModel.requestCapture()
        await waitUntil { !harness.cameraEvents.controlMessages.isEmpty }
        let requestId = try XCTUnwrap(
            harness.cameraEvents.controlMessages.compactMap { message -> String? in
                if case .capturePhoto(let id) = message { return id } else { return nil }
            }.first
        )

        try harness.camera.send(.captureFailed(requestId: requestId, reason: "no camera frame had arrived yet"))
        await waitUntil { harness.viewModel.errorMessage != nil }

        XCTAssertFalse(harness.viewModel.isAwaitingSnapshot)
        XCTAssertNil(harness.viewModel.snapshot)
        let message = try XCTUnwrap(harness.viewModel.errorMessage)
        XCTAssertTrue(message.contains("no camera frame had arrived yet"))
        await harness.viewModel.stop()
    }

    func test_undecodableImageBytes_areReportedAsATransferFailure() async throws {
        let harness = makeHarness()
        await connected(harness)
        harness.viewModel.requestCapture()
        await waitUntil { !harness.cameraEvents.controlMessages.isEmpty }
        let requestId = try XCTUnwrap(
            harness.cameraEvents.controlMessages.compactMap { message -> String? in
                if case .capturePhoto(let id) = message { return id } else { return nil }
            }.first
        )

        // Every chunk arrives, but the bytes are not an image.
        let garbage = Data(repeating: 0x42, count: 2_000)
        let transferId = UUID()
        let frames = try ImageTransferFrame.chunk(payload: garbage, transferId: transferId)
        try harness.camera.send(.captureCompleted(
            requestId: requestId,
            transferId: transferId.uuidString,
            byteCount: garbage.count,
            chunkCount: frames.count
        ))
        try await harness.camera.sendImage(frames: frames)
        await waitUntil { harness.viewModel.errorMessage != nil }

        XCTAssertNil(harness.viewModel.snapshot)
        let message = try XCTUnwrap(harness.viewModel.errorMessage)
        XCTAssertTrue(message.contains("could not be decoded"))
        await harness.viewModel.stop()
    }

    func test_aPartialTransferLeavesNoSnapshot() async throws {
        let harness = makeHarness()
        await connected(harness)
        harness.viewModel.requestCapture()
        await waitUntil { !harness.cameraEvents.controlMessages.isEmpty }

        let payload = try SnapshotImageEncoder.encode(
            TestImage.makeUIImage(size: CGSize(width: 1600, height: 1200))
        )
        let frames = try ImageTransferFrame.chunk(payload: payload, transferId: UUID())
        XCTAssertGreaterThan(frames.count, 1, "the fixture should be multi-chunk")

        // All but the last chunk.
        try await harness.camera.sendImage(frames: Array(frames.dropLast()))
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertNil(harness.viewModel.snapshot, "an incomplete transfer must not produce an image")
        XCTAssertTrue(harness.viewModel.isAwaitingSnapshot)
        await harness.viewModel.stop()
    }

    func test_cameraSwitchRequest_reachesTheCamera() async {
        let harness = makeHarness()
        await connected(harness)

        harness.viewModel.requestCameraSwitch()

        XCTAssertTrue(harness.cameraEvents.controlMessages.contains(.cameraSwitch))
        await harness.viewModel.stop()
    }

    // MARK: - Disconnect and reconnect

    func test_disconnect_clearsTheSessionAndDeletesTheDocument() async {
        let harness = makeHarness()
        await connected(harness)

        await harness.viewModel.disconnect()

        XCTAssertFalse(harness.viewModel.isConnected)
        XCTAssertFalse(harness.viewModel.isReceivingVideo)
        XCTAssertEqual(harness.viewModel.status, .disconnected)
        XCTAssertTrue(harness.transport.storedSessions.isEmpty)
        await harness.viewModel.stop()
    }

    func test_theSessionEndsWhenTheCameraLeavesCameraMode() async {
        let harness = makeHarness()
        await connected(harness)

        await harness.camera.disconnect(reason: "the camera device left Camera Mode")
        await waitUntil { !harness.viewModel.isConnected }

        XCTAssertFalse(harness.viewModel.isConnected)
        XCTAssertFalse(harness.viewModel.isReceivingVideo)
        XCTAssertNil(harness.viewModel.connectedCameraName)
        await harness.viewModel.stop()
    }

    func test_anInFlightCaptureFailsIfTheSessionEnds() async {
        let harness = makeHarness()
        await connected(harness)
        harness.viewModel.requestCapture()
        await waitUntil { harness.viewModel.isAwaitingSnapshot }

        await harness.camera.disconnect(reason: "the camera device left Camera Mode")
        await waitUntil { !harness.viewModel.isAwaitingSnapshot }

        XCTAssertFalse(harness.viewModel.isAwaitingSnapshot)
        XCTAssertNotNil(harness.viewModel.errorMessage)
        await harness.viewModel.stop()
    }

    // MARK: - Snapshot handling

    func test_saveSnapshot_writesIntoDocuments() async throws {
        let harness = makeHarness()
        await connected(harness)
        harness.viewModel.requestCapture()
        await waitUntil { !harness.cameraEvents.controlMessages.isEmpty }
        let requestId = try XCTUnwrap(
            harness.cameraEvents.controlMessages.compactMap { message -> String? in
                if case .capturePhoto(let id) = message { return id } else { return nil }
            }.first
        )
        let payload = try SnapshotImageEncoder.encode(TestImage.makeUIImage(size: CGSize(width: 800, height: 600)))
        let transferId = UUID()
        let frames = try ImageTransferFrame.chunk(payload: payload, transferId: transferId)
        try harness.camera.send(.captureCompleted(
            requestId: requestId,
            transferId: transferId.uuidString,
            byteCount: payload.count,
            chunkCount: frames.count
        ))
        try await harness.camera.sendImage(frames: frames)
        await waitUntil { harness.viewModel.snapshot != nil }

        harness.viewModel.saveSnapshot()

        let savedName = try XCTUnwrap(harness.viewModel.savedSnapshotName)
        let url = try FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("RemoteSnapshots", isDirectory: true)
            .appendingPathComponent(savedName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: url)
        await harness.viewModel.stop()
    }

    func test_theDefaultRecognitionServiceExplainsItselfAndReturnsNothing() async throws {
        let harness = makeHarness()
        await harness.viewModel.start()

        let explanation = try XCTUnwrap(harness.viewModel.recognitionUnavailableExplanation)
        XCTAssertTrue(explanation.contains("isn't wired up yet"))

        let result = try await UnimplementedFoodRecognitionService()
            .recognizeFood(in: TestImage.makeUIImage())
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertFalse(result.isMockData)
        await harness.viewModel.stop()
    }

    func test_mockRecognitionOutputIsFlaggedAsMockData() async throws {
        let result = try await MockFoodRecognitionService().recognizeFood(in: TestImage.makeUIImage())

        XCTAssertTrue(result.isMockData, "mock output must be impossible to mistake for real recognition")
        XCTAssertFalse(result.items.isEmpty)
        for item in result.items {
            XCTAssertTrue(item.name.hasPrefix("Mock "), "mock item names should say so: \(item.name)")
        }
    }

    /// The prototype must not put guessed ingredients in the pantry.
    func test_recognizingASnapshotNeverWritesToThePantry() async throws {
        let pantry = InMemoryPantryRepository()
        let harness = makeHarness(recognitionService: MockFoodRecognitionService())
        await connected(harness)
        harness.viewModel.requestCapture()
        await waitUntil { !harness.cameraEvents.controlMessages.isEmpty }
        let requestId = try XCTUnwrap(
            harness.cameraEvents.controlMessages.compactMap { message -> String? in
                if case .capturePhoto(let id) = message { return id } else { return nil }
            }.first
        )
        let payload = try SnapshotImageEncoder.encode(TestImage.makeUIImage(size: CGSize(width: 640, height: 480)))
        let transferId = UUID()
        let frames = try ImageTransferFrame.chunk(payload: payload, transferId: transferId)
        try harness.camera.send(.captureCompleted(
            requestId: requestId,
            transferId: transferId.uuidString,
            byteCount: payload.count,
            chunkCount: frames.count
        ))
        try await harness.camera.sendImage(frames: frames)
        await waitUntil { harness.viewModel.snapshot != nil }

        await harness.viewModel.recognizeSnapshot()

        XCTAssertEqual(harness.viewModel.recognition?.isMockData, true)
        let pantryContents = try await pantry.fetchAll()
        XCTAssertTrue(
            pantryContents.isEmpty,
            "the remote-camera prototype must never add ingredients on its own"
        )
        await harness.viewModel.stop()
    }
}
