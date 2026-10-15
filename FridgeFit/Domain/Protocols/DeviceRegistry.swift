//
//  DeviceRegistry.swift
//  FridgeFit
//

import Foundation

/// A cancellable observation. Returned by the live-update methods on
/// `DeviceRegistry` and `SignalingTransport` so callers can tear listeners
/// down without knowing they're Firestore snapshot listeners underneath.
nonisolated protocol RemoteSubscription: AnyObject, Sendable {
    func cancel()
}

/// A `RemoteSubscription` that runs a closure on cancel.
nonisolated final class ClosureSubscription: RemoteSubscription, @unchecked Sendable {
    private let lock = NSLock()
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    /// Idempotent - a view that cancels in `onDisappear` and again in
    /// `deinit` must not run the teardown twice.
    func cancel() {
        lock.lock()
        let work = onCancel
        onCancel = nil
        lock.unlock()
        work?()
    }

    deinit {
        cancel()
    }
}

/// Where devices announce themselves to the other devices on the account.
///
/// Abstracted so the discovery and presence logic can be tested against an
/// in-memory store, the same way `PantryRepository` lets the use cases be
/// tested without Firestore.
nonisolated protocol DeviceRegistry: AnyObject, Sendable {
    /// Creates or refreshes this device's document.
    ///
    /// Must be idempotent: called on every app launch and on every role
    /// change, and must not reset `createdAt`.
    func register(device: RegisteredDevice) async throws

    /// Refreshes `lastSeenAt` (and optionally the status) without touching
    /// anything else. This is the heartbeat.
    func heartbeat(deviceId: String, status: DeviceConnectionStatus?) async throws

    /// Publishes a status change immediately rather than waiting for the next
    /// heartbeat.
    func updateStatus(deviceId: String, status: DeviceConnectionStatus) async throws

    func updateRole(deviceId: String, role: DeviceRole) async throws

    /// Every device on the account, including this one. Filtering self out is
    /// the caller's job - it needs the self entry to show "this device".
    func observeDevices(onChange: @escaping @MainActor ([RegisteredDevice]) -> Void,
                        onError: @escaping @MainActor (Error) -> Void) -> RemoteSubscription

    func fetchDevices() async throws -> [RegisteredDevice]
}
