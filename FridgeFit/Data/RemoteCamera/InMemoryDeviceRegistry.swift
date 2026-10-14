//
//  InMemoryDeviceRegistry.swift
//  FridgeFit
//

import Foundation

/// In-memory `DeviceRegistry` standing in for one Firebase account's
/// `users/{uid}/devices` collection.
///
/// Lives in the app target next to `InMemoryPantryRepository`, for the same
/// reason: it is the double the tests use, and keeping it beside the real
/// implementation means both stay in step when the protocol changes.
///
/// One instance represents one account. Two devices on the same account
/// share an instance; modelling "different accounts" is a matter of giving
/// each device its own instance, which is exactly what makes them unable to
/// discover each other.
nonisolated final class InMemoryDeviceRegistry: DeviceRegistry, @unchecked Sendable {
    private let lock = NSLock()
    private var devices: [String: RegisteredDevice] = [:]
    private var observers: [UUID: @MainActor ([RegisteredDevice]) -> Void] = [:]
    /// Injectable so presence/staleness can be tested without sleeping for
    /// `RegisteredDevice.presenceWindow`.
    private let now: @Sendable () -> Date

    /// Set to make every call throw, for testing the signed-out path.
    var failureToThrow: Error?

    init(seedDevices: [RegisteredDevice] = [], now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
        for device in seedDevices {
            devices[device.deviceId] = device
        }
    }

    var storedDevices: [RegisteredDevice] {
        lock.lock()
        defer { lock.unlock() }
        return devices.values.sorted { $0.deviceId < $1.deviceId }
    }

    func register(device: RegisteredDevice) async throws {
        try throwIfFailing()
        mutate { devices in
            // Preserve `createdAt` on re-registration, matching the Firestore
            // implementation's merge-without-createdAt behaviour.
            let createdAt = devices[device.deviceId]?.createdAt ?? device.createdAt
            devices[device.deviceId] = RegisteredDevice(
                deviceId: device.deviceId,
                deviceName: device.deviceName,
                deviceRole: device.deviceRole,
                connectionStatus: device.connectionStatus,
                lastSeenAt: device.lastSeenAt,
                createdAt: createdAt
            )
        }
    }

    func heartbeat(deviceId: String, status: DeviceConnectionStatus?) async throws {
        try throwIfFailing()
        let timestamp = now()
        mutate { devices in
            guard let existing = devices[deviceId] else { return }
            devices[deviceId] = RegisteredDevice(
                deviceId: existing.deviceId,
                deviceName: existing.deviceName,
                deviceRole: existing.deviceRole,
                connectionStatus: status ?? existing.connectionStatus,
                lastSeenAt: timestamp,
                createdAt: existing.createdAt
            )
        }
    }

    func updateStatus(deviceId: String, status: DeviceConnectionStatus) async throws {
        try await heartbeat(deviceId: deviceId, status: status)
    }

    func updateRole(deviceId: String, role: DeviceRole) async throws {
        try throwIfFailing()
        let timestamp = now()
        mutate { devices in
            guard let existing = devices[deviceId] else { return }
            devices[deviceId] = RegisteredDevice(
                deviceId: existing.deviceId,
                deviceName: existing.deviceName,
                deviceRole: role,
                connectionStatus: existing.connectionStatus,
                lastSeenAt: timestamp,
                createdAt: existing.createdAt
            )
        }
    }

    func observeDevices(
        onChange: @escaping @MainActor ([RegisteredDevice]) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) -> RemoteSubscription {
        if let failureToThrow {
            Task { @MainActor in onError(failureToThrow) }
            return ClosureSubscription {}
        }
        let token = UUID()
        lock.lock()
        observers[token] = onChange
        let snapshot = devices.values.sorted { $0.deviceId < $1.deviceId }
        lock.unlock()

        // Fire with the current contents on attach, like a Firestore listener.
        Task { @MainActor in onChange(snapshot) }
        return ClosureSubscription { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.observers[token] = nil
            self.lock.unlock()
        }
    }

    func fetchDevices() async throws -> [RegisteredDevice] {
        try throwIfFailing()
        return storedDevices
    }

    private func throwIfFailing() throws {
        if let failureToThrow { throw failureToThrow }
    }

    private func mutate(_ work: (inout [String: RegisteredDevice]) -> Void) {
        lock.lock()
        work(&devices)
        let snapshot = devices.values.sorted { $0.deviceId < $1.deviceId }
        let listeners = Array(observers.values)
        lock.unlock()
        for listener in listeners {
            Task { @MainActor in listener(snapshot) }
        }
    }
}
