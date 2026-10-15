//
//  RegisteredDevice.swift
//  FridgeFit
//

import Foundation

/// One install of FridgeFit, as seen by the other installs on the same
/// Firebase account.
///
/// Firebase gives us a UID per *account*, which says nothing about which
/// phone is which - two iPhones signed into the same account are
/// indistinguishable at the auth layer. So each install mints its own
/// `deviceId` (see `DeviceIdentity`) and publishes a document at
/// `users/{uid}/devices/{deviceId}`.
nonisolated struct RegisteredDevice: Identifiable, Equatable, Sendable {
    /// Stable per-install identifier. Also the Firestore document ID.
    let deviceId: String
    /// Human-readable, from `UIDevice.name` at registration time.
    let deviceName: String
    let deviceRole: DeviceRole
    /// What the device last said about itself. Never trusted on its own -
    /// always read through `effectiveStatus`.
    let connectionStatus: DeviceConnectionStatus
    /// Last heartbeat. Drives presence.
    let lastSeenAt: Date
    let createdAt: Date

    var id: String { deviceId }

    /// How long a device may go without a heartbeat before the other side
    /// stops believing it's there.
    ///
    /// Three missed heartbeats at `DeviceHeartbeat.interval` (10s). Long
    /// enough to ride out a slow Firestore write, short enough that a
    /// force-quit camera drops off the list while the user is still looking
    /// at it.
    static let presenceWindow: TimeInterval = 35

    /// Whether this device has heartbeated recently enough to be believed.
    ///
    /// This is the half that survives a crash: a device that died holding a
    /// `connected` status simply stops heartbeating, and every other device
    /// independently concludes it's gone. No cleanup write required from the
    /// device that failed.
    func isPresent(now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastSeenAt) <= Self.presenceWindow
    }

    /// The status to actually show and act on.
    ///
    /// Collapses a stale heartbeat to `.offline` no matter what the document
    /// claims, which is what stops ghost "online" cameras accumulating.
    func effectiveStatus(now: Date = Date()) -> DeviceConnectionStatus {
        isPresent(now: now) ? connectionStatus : .offline
    }
}

// MARK: - Firestore field mapping
//
// Pure static functions with no Firestore types in the signature, for the
// same reason `FirestorePantryRepository` does it this way: the field
// mapping is the part worth unit testing, and it shouldn't need a live
// project to test.

nonisolated extension RegisteredDevice {
    enum Field {
        static let deviceId = "deviceId"
        static let deviceName = "deviceName"
        static let deviceRole = "deviceRole"
        static let connectionStatus = "connectionStatus"
        static let lastSeenAt = "lastSeenAt"
        static let createdAt = "createdAt"
    }

    /// Decodes a device document.
    ///
    /// `lastSeenAt`/`createdAt` arrive as `Date` once the Firestore layer has
    /// unwrapped its `Timestamp`, so this stays Firestore-agnostic. A
    /// document still holding an unresolved server timestamp (`nil`) decodes
    /// with `lastSeenAt` at `.distantPast`, which reads as offline - the
    /// right answer for a registration write we haven't seen land yet.
    static func decode(id: String, data: [String: Any]) -> RegisteredDevice? {
        guard
            let name = data[Field.deviceName] as? String,
            let roleRaw = data[Field.deviceRole] as? String,
            let role = DeviceRole(rawValue: roleRaw)
        else {
            return nil
        }
        let statusRaw = data[Field.connectionStatus] as? String
        let status = statusRaw.flatMap(DeviceConnectionStatus.init(rawValue:)) ?? .offline
        return RegisteredDevice(
            deviceId: id,
            deviceName: name,
            deviceRole: role,
            connectionStatus: status,
            lastSeenAt: data[Field.lastSeenAt] as? Date ?? .distantPast,
            createdAt: data[Field.createdAt] as? Date ?? .distantPast
        )
    }
}
