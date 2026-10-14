//
//  FirestoreDeviceRegistry.swift
//  FridgeFit
//

import FirebaseAuth
@preconcurrency import FirebaseFirestore
import Foundation

/// Firestore-backed `DeviceRegistry`, at `users/{uid}/devices/{deviceId}`.
///
/// Scoped under the UID exactly like `FirestorePantryRepository`, which is
/// what makes "same account" the discovery boundary: a device can only ever
/// see devices written under its own authenticated UID, so two phones on
/// different accounts cannot find each other no matter what they publish.
///
/// Every call goes through `FirestoreDiagnostics`, so a refusal arrives with
/// the operation, path and auth state attached instead of a bare "Missing or
/// insufficient permissions".
nonisolated final class FirestoreDeviceRegistry: DeviceRegistry {
    private let firestore: Firestore
    private let userIDProvider: @Sendable () -> String?

    init(
        firestore: Firestore = Firestore.firestore(),
        userIDProvider: @escaping @Sendable () -> String? = { Auth.auth().currentUser?.uid }
    ) {
        self.firestore = firestore
        self.userIDProvider = userIDProvider
    }

    /// - Throws: `RemoteCameraError.notAuthenticated` when signed out. Never
    ///   falls back to an unscoped path.
    private func devicesCollection() throws -> CollectionReference {
        guard let uid = userIDProvider(), !uid.isEmpty else {
            throw RemoteCameraError.notAuthenticated
        }
        return firestore.collection("users").document(uid).collection("devices")
    }

    private func devicePath(_ deviceId: String) -> String {
        "users/{uid}/devices/\(deviceId)"
    }

    private var collectionPath: String { "users/{uid}/devices" }

    func register(device: RegisteredDevice) async throws {
        let uid = userIDProvider()
        let document = try devicesCollection().document(device.deviceId)
        var fields: [String: Any] = [
            RegisteredDevice.Field.deviceId: device.deviceId,
            RegisteredDevice.Field.deviceName: device.deviceName,
            RegisteredDevice.Field.deviceRole: device.deviceRole.rawValue,
            RegisteredDevice.Field.connectionStatus: device.connectionStatus.rawValue,
            RegisteredDevice.Field.lastSeenAt: FieldValue.serverTimestamp(),
        ]

        // Only set on first write. A merge that included it would reset the
        // creation time on every launch.
        let existing = try await FirestoreDiagnostics.perform(
            .read, path: devicePath(device.deviceId), uid: uid
        ) {
            try await document.getDocument()
        }
        if !existing.exists {
            fields[RegisteredDevice.Field.createdAt] = FieldValue.serverTimestamp()
        }

        try await FirestoreDiagnostics.perform(
            existing.exists ? .update : .create, path: devicePath(device.deviceId), uid: uid
        ) {
            try await document.setData(fields, merge: true)
        }
    }

    func heartbeat(deviceId: String, status: DeviceConnectionStatus?) async throws {
        let uid = userIDProvider()
        var fields: [String: Any] = [
            RegisteredDevice.Field.lastSeenAt: FieldValue.serverTimestamp(),
        ]
        if let status {
            fields[RegisteredDevice.Field.connectionStatus] = status.rawValue
        }
        let document = try devicesCollection().document(deviceId)
        // `merge` rather than `updateData`: a heartbeat racing a sign-out that
        // wiped the document should re-create it, not throw.
        try await FirestoreDiagnostics.perform(.update, path: devicePath(deviceId), uid: uid) {
            try await document.setData(fields, merge: true)
        }
    }

    func updateStatus(deviceId: String, status: DeviceConnectionStatus) async throws {
        let uid = userIDProvider()
        let document = try devicesCollection().document(deviceId)
        try await FirestoreDiagnostics.perform(.update, path: devicePath(deviceId), uid: uid) {
            try await document.setData([
                RegisteredDevice.Field.connectionStatus: status.rawValue,
                RegisteredDevice.Field.lastSeenAt: FieldValue.serverTimestamp(),
            ], merge: true)
        }
    }

    func updateRole(deviceId: String, role: DeviceRole) async throws {
        let uid = userIDProvider()
        let document = try devicesCollection().document(deviceId)
        try await FirestoreDiagnostics.perform(.update, path: devicePath(deviceId), uid: uid) {
            try await document.setData([
                RegisteredDevice.Field.deviceRole: role.rawValue,
                RegisteredDevice.Field.lastSeenAt: FieldValue.serverTimestamp(),
            ], merge: true)
        }
    }

    func observeDevices(
        onChange: @escaping @MainActor ([RegisteredDevice]) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) -> RemoteSubscription {
        // The provider, not a snapshotted value: re-read on failure so a
        // sign-out is reported as such.
        let currentUID = userIDProvider
        let collection: CollectionReference
        do {
            collection = try devicesCollection()
        } catch {
            Task { @MainActor in onError(error) }
            return ClosureSubscription {}
        }

        let path = collectionPath
        let registration = collection.addSnapshotListener { snapshot, error in
            if let error {
                // Re-read auth here rather than using the uid captured
                // when the listener attached: if the user signed out in the
                // meantime, that is the real cause and it should be reported
                // as `notAuthenticated`, not as a rules problem.
                let reported = FirestoreDiagnostics.report(
                    error, operation: .listen, path: path, uid: currentUID()
                )
                Task { @MainActor in onError(reported) }
                return
            }
            guard let snapshot else { return }
            let devices = snapshot.documents.compactMap {
                RegisteredDevice.decode(id: $0.documentID, data: Self.withResolvedDates($0.data()))
            }
            Task { @MainActor in onChange(devices) }
        }
        return ClosureSubscription { registration.remove() }
    }

    func fetchDevices() async throws -> [RegisteredDevice] {
        let uid = userIDProvider()
        let collection = try devicesCollection()
        let snapshot = try await FirestoreDiagnostics.perform(.list, path: collectionPath, uid: uid) {
            try await collection.getDocuments()
        }
        return snapshot.documents.compactMap {
            RegisteredDevice.decode(id: $0.documentID, data: Self.withResolvedDates($0.data()))
        }
    }

    /// Converts Firestore `Timestamp` values to `Date` so the decoders in
    /// `RegisteredDevice` stay Firestore-agnostic and unit testable.
    ///
    /// A field still holding an unresolved server timestamp comes through as
    /// `nil` and is simply dropped - `RegisteredDevice.decode` treats a
    /// missing `lastSeenAt` as `.distantPast`, i.e. offline, which is the
    /// honest reading of a write we haven't seen land.
    static func withResolvedDates(_ data: [String: Any]) -> [String: Any] {
        var resolved = data
        for (key, value) in data {
            if let timestamp = value as? Timestamp {
                resolved[key] = timestamp.dateValue()
            }
        }
        return resolved
    }
}
