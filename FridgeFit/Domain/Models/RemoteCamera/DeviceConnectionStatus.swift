//
//  DeviceConnectionStatus.swift
//  FridgeFit
//

import Foundation

/// The lifecycle a remote-camera link moves through, shared by both ends so
/// the two screens describe the same situation with the same word.
///
/// `offline` is deliberately not something a device ever writes about
/// itself - it's what the *other* side infers when a heartbeat goes stale
/// (see `RegisteredDevice.isPresent`). A device that crashes can't update
/// its own document, so trusting a stored "connected" would leave ghost
/// cameras in the list forever.
nonisolated enum DeviceConnectionStatus: String, Codable, CaseIterable, Sendable {
    /// Not running the app, or last heartbeat is older than the presence window.
    case offline
    /// Registered, heartbeating, and idle - ready to be connected to.
    case available
    /// Signaling is in flight (offer/answer/ICE), no media yet.
    case connecting
    /// ICE is connected and media/data should be flowing.
    case connected
    /// ICE dropped but WebRTC is still trying to recover the same session.
    case reconnecting
    /// The session ended cleanly, from either side.
    case disconnected
    /// The session ended badly - negotiation or ICE could not succeed.
    case failed

    var displayName: String {
        switch self {
        case .offline: return "Offline"
        case .available: return "Available"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting"
        case .disconnected: return "Disconnected"
        case .failed: return "Failed"
        }
    }

    /// Whether this device can be the target of a new connection attempt.
    var isConnectable: Bool {
        switch self {
        case .available, .disconnected, .failed:
            return true
        case .offline, .connecting, .connected, .reconnecting:
            return false
        }
    }

    /// Whether a session is live enough that media is expected.
    ///
    /// Used to keep the UI honest: "Connected" is only shown once ICE says
    /// so, never just because signaling documents were written.
    var isLive: Bool {
        self == .connected
    }
}
