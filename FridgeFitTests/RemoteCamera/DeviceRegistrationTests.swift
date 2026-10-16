//
//  DeviceRegistrationTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// Test B: two distinct device IDs living under one Firebase account, plus
/// the presence rules that stop a crashed device lingering as "available".
@MainActor
final class DeviceRegistrationTests: XCTestCase {

    private func makeIdentity(_ suffix: String, name: String) -> DeviceIdentity {
        DeviceIdentity(deviceId: "device-\(suffix)", deviceName: name)
    }

    // MARK: - Two devices, one account

    func test_twoDevices_registerDistinctIdsUnderOneAccount() async throws {
        // One registry instance is one account's `users/{uid}/devices`.
        let account = InMemoryDeviceRegistry()
        let phoneA = makeIdentity("a", name: "Kitchen iPhone")
        let phoneB = makeIdentity("b", name: "Pocket iPhone")

        try await account.register(device: phoneA.asRegisteredDevice(role: .camera))
        try await account.register(device: phoneB.asRegisteredDevice(role: .controller))

        let devices = try await account.fetchDevices()
        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(Set(devices.map(\.deviceId)), ["device-a", "device-b"])
        XCTAssertEqual(devices.first { $0.deviceId == "device-a" }?.deviceRole, .camera)
        XCTAssertEqual(devices.first { $0.deviceId == "device-b" }?.deviceRole, .controller)
    }

    func test_eachDeviceDiscoversTheOtherButNotItself() async throws {
        let account = InMemoryDeviceRegistry()
        let camera = makeIdentity("camera", name: "Kitchen iPhone")
        let controller = makeIdentity("controller", name: "Pocket iPhone")
        try await account.register(device: camera.asRegisteredDevice(role: .camera))
        try await account.register(device: controller.asRegisteredDevice(role: .controller))

        let viewModel = ConnectedDevicesViewModel(identity: controller, registry: account)
        await viewModel.start()
        await settle()

        XCTAssertEqual(viewModel.otherDevices.map(\.deviceId), ["device-camera"])
        XCTAssertEqual(viewModel.availableCameras.map(\.deviceName), ["Kitchen iPhone"])
        XCTAssertFalse(
            viewModel.otherDevices.contains { $0.deviceId == controller.deviceId },
            "a device must never list itself as connectable"
        )
        viewModel.stop()
    }

    /// Error case 2: different accounts. Separate registry instances model
    /// separate `users/{uid}` subtrees, which is exactly what the Firestore
    /// rules enforce - there is no cross-account read to filter out.
    func test_devicesOnDifferentAccountsCannotSeeEachOther() async throws {
        let accountOne = InMemoryDeviceRegistry()
        let accountTwo = InMemoryDeviceRegistry()
        let phoneA = makeIdentity("a", name: "A")
        let phoneB = makeIdentity("b", name: "B")

        try await accountOne.register(device: phoneA.asRegisteredDevice(role: .camera))
        try await accountTwo.register(device: phoneB.asRegisteredDevice(role: .controller))

        let visibleToAccountOne = try await accountOne.fetchDevices().map(\.deviceId)
        let visibleToAccountTwo = try await accountTwo.fetchDevices().map(\.deviceId)

        XCTAssertEqual(visibleToAccountOne, ["device-a"])
        XCTAssertEqual(visibleToAccountTwo, ["device-b"])
    }

    /// Error case 1: nothing to discover. The message has to tell the user
    /// what to do on the other phone, not just report emptiness.
    func test_noCameraDevices_producesAnActionableMessage() async throws {
        let account = InMemoryDeviceRegistry()
        let controller = makeIdentity("controller", name: "Pocket iPhone")
        try await account.register(device: controller.asRegisteredDevice(role: .controller))

        let viewModel = ConnectedDevicesViewModel(identity: controller, registry: account)
        await viewModel.start()
        await settle()

        XCTAssertTrue(viewModel.availableCameras.isEmpty)
        XCTAssertTrue(RemoteCameraError.noCameraDevicesFound.message.contains("Camera Mode"))
        viewModel.stop()
    }

    // MARK: - Roles

    func test_aDeviceCanSwitchRoles() async throws {
        let account = InMemoryDeviceRegistry()
        let identity = makeIdentity("a", name: "Kitchen iPhone")
        try await account.register(device: identity.asRegisteredDevice(role: .controller))

        try await account.updateRole(deviceId: identity.deviceId, role: .camera)

        let roleAfterSwitch = try await account.fetchDevices().first?.deviceRole
        XCTAssertEqual(roleAfterSwitch, .camera)
    }

    func test_reRegistering_preservesTheOriginalCreationTime() async throws {
        let account = InMemoryDeviceRegistry()
        let identity = makeIdentity("a", name: "Kitchen iPhone")
        let firstSeen = Date(timeIntervalSince1970: 1_000)
        try await account.register(device: identity.asRegisteredDevice(role: .controller, at: firstSeen))

        // Relaunch: same device registers again, much later.
        try await account.register(
            device: identity.asRegisteredDevice(role: .camera, at: Date(timeIntervalSince1970: 50_000))
        )

        let stored = try await account.fetchDevices()
        let device = try XCTUnwrap(stored.first)
        XCTAssertEqual(device.createdAt, firstSeen, "createdAt must not be reset on every launch")
        XCTAssertEqual(device.deviceRole, .camera)
    }

    // MARK: - Presence

    func test_aDeviceWithARecentHeartbeatIsPresent() {
        let now = Date(timeIntervalSince1970: 10_000)
        let device = RegisteredDevice(
            deviceId: "a",
            deviceName: "A",
            deviceRole: .camera,
            connectionStatus: .available,
            lastSeenAt: now.addingTimeInterval(-5),
            createdAt: now
        )

        XCTAssertTrue(device.isPresent(now: now))
        XCTAssertEqual(device.effectiveStatus(now: now), .available)
    }

    /// The crash path. A force-quit device cannot write "offline", so a
    /// stored `connected` has to be overridden by the stale heartbeat -
    /// otherwise the device list accumulates cameras that aren't there.
    func test_aStaleHeartbeatOverridesAStoredConnectedStatus() {
        let now = Date(timeIntervalSince1970: 10_000)
        let crashedWhileConnected = RegisteredDevice(
            deviceId: "a",
            deviceName: "A",
            deviceRole: .camera,
            connectionStatus: .connected,
            lastSeenAt: now.addingTimeInterval(-(RegisteredDevice.presenceWindow + 1)),
            createdAt: now
        )

        XCTAssertFalse(crashedWhileConnected.isPresent(now: now))
        XCTAssertEqual(crashedWhileConnected.effectiveStatus(now: now), .offline)
    }

    func test_presenceWindow_allowsThreeMissedHeartbeats() {
        let beatsInsideWindow = RegisteredDevice.presenceWindow / Double(DeviceHeartbeat.interval.components.seconds)

        XCTAssertGreaterThanOrEqual(
            beatsInsideWindow,
            3,
            "one dropped Firestore write must not make a live device look offline"
        )
    }

    func test_aStaleCameraIsFilteredOutOfTheAvailableList() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let account = InMemoryDeviceRegistry(seedDevices: [
            RegisteredDevice(
                deviceId: "fresh-camera",
                deviceName: "Fresh",
                deviceRole: .camera,
                connectionStatus: .available,
                lastSeenAt: now.addingTimeInterval(-2),
                createdAt: now
            ),
            RegisteredDevice(
                deviceId: "stale-camera",
                deviceName: "Stale",
                deviceRole: .camera,
                connectionStatus: .available,
                lastSeenAt: now.addingTimeInterval(-600),
                createdAt: now
            ),
        ])
        let controller = makeIdentity("controller", name: "Pocket iPhone")

        let viewModel = ConnectedDevicesViewModel(
            identity: controller,
            registry: account,
            now: { now }
        )
        await viewModel.start()
        await settle()

        XCTAssertEqual(viewModel.availableCameras.map(\.deviceId), ["fresh-camera"])
        viewModel.stop()
    }

    // MARK: - Field mapping

    func test_decode_readsADeviceDocument() throws {
        let lastSeen = Date(timeIntervalSince1970: 5_000)
        let created = Date(timeIntervalSince1970: 1_000)

        let device = try XCTUnwrap(RegisteredDevice.decode(id: "device-a", data: [
            "deviceId": "device-a",
            "deviceName": "Kitchen iPhone",
            "deviceRole": "camera",
            "connectionStatus": "connected",
            "lastSeenAt": lastSeen,
            "createdAt": created,
        ]))

        XCTAssertEqual(device.deviceId, "device-a")
        XCTAssertEqual(device.deviceName, "Kitchen iPhone")
        XCTAssertEqual(device.deviceRole, .camera)
        XCTAssertEqual(device.connectionStatus, .connected)
        XCTAssertEqual(device.lastSeenAt, lastSeen)
        XCTAssertEqual(device.createdAt, created)
    }

    func test_decode_rejectsADocumentWithAnUnknownRole() {
        XCTAssertNil(RegisteredDevice.decode(id: "device-a", data: [
            "deviceName": "A",
            "deviceRole": "projector",
        ]))
    }

    func test_decode_rejectsADocumentWithNoName() {
        XCTAssertNil(RegisteredDevice.decode(id: "device-a", data: ["deviceRole": "camera"]))
    }

    /// A document whose `lastSeenAt` server timestamp hasn't resolved yet
    /// reads as offline, which is the honest answer for a write we haven't
    /// seen land.
    func test_decode_treatsAMissingHeartbeatAsOffline() throws {
        let device = try XCTUnwrap(RegisteredDevice.decode(id: "device-a", data: [
            "deviceName": "A",
            "deviceRole": "camera",
            "connectionStatus": "connected",
        ]))

        XCTAssertEqual(device.lastSeenAt, .distantPast)
        XCTAssertEqual(device.effectiveStatus(now: Date()), .offline)
    }

    func test_decode_treatsAnUnknownStatusAsOffline() throws {
        let device = try XCTUnwrap(RegisteredDevice.decode(id: "device-a", data: [
            "deviceName": "A",
            "deviceRole": "camera",
            "connectionStatus": "gone-fishing",
            "lastSeenAt": Date(),
        ]))

        XCTAssertEqual(device.connectionStatus, .offline)
    }

    // MARK: - Device identity

    func test_deviceId_isStableAcrossReads() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DeviceRegistrationTests.stable"))
        defaults.removePersistentDomain(forName: "DeviceRegistrationTests.stable")

        let first = DeviceIdentity.current(defaults: defaults, deviceName: "Test iPhone")
        let second = DeviceIdentity.current(defaults: defaults, deviceName: "Test iPhone")

        XCTAssertEqual(first.deviceId, second.deviceId)
        XCTAssertFalse(first.deviceId.isEmpty)
    }

    func test_twoSeparateInstalls_mintDifferentDeviceIds() throws {
        let installA = try XCTUnwrap(UserDefaults(suiteName: "DeviceRegistrationTests.installA"))
        let installB = try XCTUnwrap(UserDefaults(suiteName: "DeviceRegistrationTests.installB"))
        installA.removePersistentDomain(forName: "DeviceRegistrationTests.installA")
        installB.removePersistentDomain(forName: "DeviceRegistrationTests.installB")

        let idA = DeviceIdentity.current(defaults: installA, deviceName: "A").deviceId
        let idB = DeviceIdentity.current(defaults: installB, deviceName: "B").deviceId

        XCTAssertNotEqual(idA, idB, "Firebase UID can't tell two installs apart, so the device ID must")
    }

    func test_identity_fallsBackWhenTheDeviceNameIsBlank() {
        let identity = DeviceIdentity.current(defaults: .standard, deviceName: "   ")

        XCTAssertEqual(identity.deviceName, "iPhone")
    }

    func test_logTag_doesNotLeakTheWholeDeviceId() {
        let identity = DeviceIdentity(deviceId: "A1B2C3D4-E5F6-0000-0000-000000000000", deviceName: "A")

        XCTAssertEqual(identity.logTag, "A1B2C3D4")
        XCTAssertLessThan(identity.logTag.count, identity.deviceId.count)
    }
}

// MARK: - Helpers

extension XCTestCase {
    /// Lets the `Task { @MainActor }` hops that both registry implementations
    /// use to deliver callbacks run before assertions.
    func settle(cycles: Int = 4) async {
        for _ in 0..<cycles {
            await Task.yield()
        }
    }
}
