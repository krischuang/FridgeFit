//
//  ConnectedDevicesViewModel.swift
//  FridgeFit
//

import Combine
import Foundation

/// Backs the Connected Devices screen: registers this device, keeps it
/// heartbeating, and lists the other devices on the same Firebase account.
@MainActor
final class ConnectedDevicesViewModel: ObservableObject {
    @Published private(set) var devices: [RegisteredDevice] = []
    @Published private(set) var role: DeviceRole
    @Published private(set) var isRegistering = false
    @Published var errorMessage: String?

    let identity: DeviceIdentity

    private let registry: any DeviceRegistry
    private let heartbeat: DeviceHeartbeat
    private let now: () -> Date
    private var subscription: RemoteSubscription?

    init(
        identity: DeviceIdentity,
        registry: any DeviceRegistry = FirestoreDeviceRegistry(),
        role: DeviceRole = DeviceIdentity.storedRole(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.identity = identity
        self.registry = registry
        self.role = role
        self.now = now
        self.heartbeat = DeviceHeartbeat(registry: registry, deviceId: identity.deviceId)
    }

    /// Releases the device listener without the main-actor hop an isolated
    /// deinit needs.
    ///
    /// SwiftUI releases a `@StateObject` from the hosting view's Objective-C
    /// ivar destructor, which is not running inside a Swift task. An isolated
    /// `deinit` - which every `@MainActor` class gets by default - has to hop
    /// to the main actor from there, and that hop corrupts the concurrency
    /// runtime's task-local stack and aborts the process. Marking the deinit
    /// `nonisolated` means no hop is attempted. Cancelling a Firestore
    /// snapshot listener is safe from any thread.
    nonisolated deinit {
        subscription?.cancel()
    }

    /// Every device on the account other than this one, most recently seen
    /// first so a phone that just came online appears at the top.
    var otherDevices: [RegisteredDevice] {
        devices
            .filter { $0.deviceId != identity.deviceId }
            .sorted { $0.lastSeenAt > $1.lastSeenAt }
    }

    /// Devices offering a camera right now.
    ///
    /// Self is excluded - the same install can be registered as a camera and
    /// then open Remote Camera, and it must not be able to pick itself.
    var availableCameras: [RegisteredDevice] {
        otherDevices.filter { $0.deviceRole == .camera && $0.isPresent(now: now()) }
    }

    func status(for device: RegisteredDevice) -> DeviceConnectionStatus {
        device.effectiveStatus(now: now())
    }

    /// Registers this device and starts watching the account's device list.
    func start() async {
        isRegistering = true
        defer { isRegistering = false }

        do {
            try await registry.register(
                device: identity.asRegisteredDevice(role: role, at: now())
            )
        } catch {
            errorMessage = Self.describe(error)
            // Still observe: a read may succeed where the write didn't, and a
            // read failure produces a clearer message through `onError`.
        }

        heartbeat.start()
        observeDevices()
    }

    /// Stops heartbeating and listening. Called when the screen goes away or
    /// the app backgrounds, so this device stops claiming to be present.
    func stop() {
        subscription?.cancel()
        subscription = nil
        heartbeat.stop()
    }

    func setRole(_ newRole: DeviceRole) async {
        guard newRole != role else { return }
        role = newRole
        DeviceIdentity.storeRole(newRole)
        do {
            try await registry.updateRole(deviceId: identity.deviceId, role: newRole)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    private func observeDevices() {
        subscription?.cancel()
        subscription = registry.observeDevices(
            onChange: { [weak self] devices in
                self?.devices = devices
            },
            onError: { [weak self] error in
                self?.errorMessage = Self.describe(error)
            }
        )
    }

    static func describe(_ error: Error) -> String {
        (error as? RemoteCameraError)?.message ?? error.localizedDescription
    }
}
