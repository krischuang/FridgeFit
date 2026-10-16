//
//  DeviceIdentity.swift
//  FridgeFit
//

import Foundation
import UIKit

/// This install's stable identity.
///
/// Firebase UID identifies the *account*, and both iPhones in this prototype
/// share one. So the app needs its own per-install ID to tell them apart,
/// and it has to survive relaunches or every launch would leave another
/// ghost device in the account's device list.
///
/// `identifierForVendor` would be the obvious candidate, but it resets when
/// the user deletes every app from the vendor, and it is the same value for
/// two installs of the same app on one device - which matters here because
/// the Simulator and a phone sharing one account is exactly the test setup.
/// A minted UUID in `UserDefaults` is simpler and has the right lifetime:
/// stable for the life of the install, gone when the app is deleted.
///
/// Not a secret and not security-relevant - it names a device inside an
/// account that Firestore rules already gate on `request.auth.uid`. It is
/// never logged alongside account identifiers.
nonisolated struct DeviceIdentity: Equatable, Sendable {
    let deviceId: String
    let deviceName: String

    private enum StorageKey {
        static let deviceId = "com.Fridge.FridgeFit.remoteCamera.deviceId"
        static let preferredRole = "com.Fridge.FridgeFit.remoteCamera.preferredRole"
    }

    /// Reads the stored ID, minting and persisting one on first call.
    ///
    /// `@MainActor` because an unsupplied `deviceName` is resolved from
    /// `UIDevice.current`, which is main-actor-isolated. Tests pass a name in
    /// and construct the value directly.
    @MainActor
    static func current(
        defaults: UserDefaults = .standard,
        deviceName: String? = nil
    ) -> DeviceIdentity {
        let deviceName = deviceName ?? UIDevice.current.name
        let storedId = defaults.string(forKey: StorageKey.deviceId)
        let deviceId: String
        if let storedId, !storedId.isEmpty {
            deviceId = storedId
        } else {
            deviceId = UUID().uuidString
            defaults.set(deviceId, forKey: StorageKey.deviceId)
        }
        let trimmedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return DeviceIdentity(
            deviceId: deviceId,
            deviceName: trimmedName.isEmpty ? "iPhone" : trimmedName
        )
    }

    /// The role this device last chose, so reopening Connected Devices doesn't
    /// silently demote a phone the user set up as a camera.
    static func storedRole(defaults: UserDefaults = .standard) -> DeviceRole {
        defaults.string(forKey: StorageKey.preferredRole)
            .flatMap(DeviceRole.init(rawValue:)) ?? .controller
    }

    static func storeRole(_ role: DeviceRole, defaults: UserDefaults = .standard) {
        defaults.set(role.rawValue, forKey: StorageKey.preferredRole)
    }

    /// This identity as a registration document, ready for
    /// `DeviceRegistry.register`.
    func asRegisteredDevice(
        role: DeviceRole,
        status: DeviceConnectionStatus = .available,
        at timestamp: Date = Date()
    ) -> RegisteredDevice {
        RegisteredDevice(
            deviceId: deviceId,
            deviceName: deviceName,
            deviceRole: role,
            connectionStatus: status,
            lastSeenAt: timestamp,
            // Ignored by `FirestoreDeviceRegistry.register` when the document
            // already exists, so re-registering never resets the real one.
            createdAt: timestamp
        )
    }

    /// A short, non-reversible tag for log lines.
    ///
    /// Device IDs are not credentials, but they are account-scoped
    /// identifiers and there is no reason for a full one to sit in a device
    /// log. Eight characters is plenty to correlate two sides of one session
    /// while reading a console.
    var logTag: String {
        String(deviceId.prefix(8))
    }
}
