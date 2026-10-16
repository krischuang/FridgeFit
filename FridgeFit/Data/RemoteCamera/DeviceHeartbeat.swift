//
//  DeviceHeartbeat.swift
//  FridgeFit
//

import Foundation
import OSLog

/// Keeps this device's `lastSeenAt` fresh while a remote-camera screen is
/// open.
///
/// Presence has to be inferred rather than declared. A device that is
/// force-quit, crashes, or loses the network cannot write "I'm gone" - so
/// instead of trusting a stored status, every device republishes a timestamp
/// and the others treat silence as absence (`RegisteredDevice.isPresent`).
/// That is what stops the device list filling up with cameras that aren't
/// there.
///
/// Deliberately tied to screen lifetime, not app lifetime: a phone that is
/// not on Camera Mode should not advertise itself as a camera.
@MainActor
final class DeviceHeartbeat {
    /// Three of these fit inside `RegisteredDevice.presenceWindow`, so one
    /// dropped write doesn't make a live device look offline.
    static let interval: Duration = .seconds(10)

    private let registry: any DeviceRegistry
    private let deviceId: String
    private let logger = Logger(subsystem: "com.Fridge.FridgeFit", category: "DeviceHeartbeat")

    private var task: Task<Void, Never>?
    private var status: DeviceConnectionStatus

    init(registry: any DeviceRegistry, deviceId: String, status: DeviceConnectionStatus = .available) {
        self.registry = registry
        self.deviceId = deviceId
        self.status = status
    }

    var isRunning: Bool { task != nil }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    try await self.registry.heartbeat(deviceId: self.deviceId, status: self.status)
                } catch {
                    // A missed beat is not worth interrupting the user for -
                    // the peer simply sees this device as offline until one
                    // lands. Logged so it is diagnosable.
                    self.logger.info("Heartbeat skipped: \(error.localizedDescription, privacy: .public)")
                }
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    /// Updates the status published by subsequent beats, and pushes it
    /// immediately so the peer doesn't wait up to `interval` to see it.
    func setStatus(_ newStatus: DeviceConnectionStatus) {
        status = newStatus
        let registry = registry
        let deviceId = deviceId
        Task {
            try? await registry.updateStatus(deviceId: deviceId, status: newStatus)
        }
    }

    /// Stops the beat without the main-actor hop an isolated deinit needs.
    ///
    /// `@MainActor` classes get an isolated `deinit`, which the runtime
    /// performs by hopping to the main actor. When one such object is
    /// released from *inside* another's isolated deinit - which is exactly
    /// what happens when a view model owning this heartbeat is torn down -
    /// the nested hop corrupts the concurrency runtime's task-local stack and
    /// aborts the process. Making this deinit `nonisolated` removes the inner
    /// hop, and nothing here needs the main actor anyway: cancelling a `Task`
    /// is safe from any thread.
    ///
    /// Deliberately does not write `offline`. A deinit has no safe way to
    /// await a Firestore round trip, and it does not need one - the peer
    /// infers absence from the stale `lastSeenAt`, which is the same
    /// mechanism that covers a crash.
    nonisolated deinit {
        task?.cancel()
    }

    /// Stops beating and marks this device offline.
    ///
    /// The explicit `offline` write is a courtesy for the clean path - the
    /// peer would work it out from the stale timestamp regardless, which is
    /// what covers the crash path.
    func stop(markOffline: Bool = true) {
        task?.cancel()
        task = nil
        guard markOffline else { return }
        let registry = registry
        let deviceId = deviceId
        Task {
            try? await registry.updateStatus(deviceId: deviceId, status: .offline)
        }
    }
}
