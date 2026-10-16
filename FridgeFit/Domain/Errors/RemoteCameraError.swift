//
//  RemoteCameraError.swift
//  FridgeFit
//

import Foundation

/// Everything the remote-camera prototype can fail at, with a message the
/// user can act on.
///
/// Deliberately explicit about the difference between "signaling worked but
/// no media arrived" (`mediaNeverArrived`) and "connected" - the one failure
/// mode a WebRTC prototype must never paper over is reporting success when
/// the video pipe is dead.
nonisolated enum RemoteCameraError: Error, Equatable, Sendable {
    /// No camera-role device is registered and heartbeating on this account.
    case noCameraDevicesFound
    /// Signed out, or the auth state changed mid-session.
    case notAuthenticated
    /// A session document named a device that isn't this one. Only reachable
    /// if two accounts somehow share a session ID, or a stale listener fires.
    case sessionNotAddressedToThisDevice
    /// The session document is gone, closed, or past its TTL.
    case sessionExpired
    /// The user declined camera access, or it's restricted.
    case cameraPermissionDenied
    /// Running somewhere without a usable capture device (Simulator).
    case cameraUnavailable
    /// ICE could not find a working path. The usual cause on different
    /// networks is no TURN server.
    case iceNegotiationFailed(turnConfigured: Bool)
    /// ICE was connected and dropped. WebRTC may still recover it.
    case connectionLost
    /// The peer said goodbye, or stopped heartbeating.
    case peerLeft(deviceName: String)
    /// Signaling succeeded and ICE connected, but no video frames arrived
    /// within the grace period.
    case mediaNeverArrived
    /// A capture round-trip failed, on either side.
    case snapshotTransferFailed(reason: String)
    /// Firestore rejected a signaling read or write.
    case signalingUnavailable(reason: String)

    var message: String {
        switch self {
        case .noCameraDevicesFound:
            return """
            No camera device found on this account. On the other iPhone, sign in \
            with the same account, open Connected Devices and tap Camera Mode. \
            It must stay on that screen to be discoverable.
            """
        case .notAuthenticated:
            return "You need to be signed in to use a remote camera."
        case .sessionNotAddressedToThisDevice:
            return "That session belongs to a different device and was ignored."
        case .sessionExpired:
            return "This session is no longer valid. Connect again to start a fresh one."
        case .cameraPermissionDenied:
            return """
            FridgeFit needs camera access to stream to your other device. \
            You can turn it on in Settings.
            """
        case .cameraUnavailable:
            return "This device doesn't have a camera available, so it can't act as a remote camera."
        case .iceNegotiationFailed(let turnConfigured):
            if turnConfigured {
                return """
                Couldn't open a direct connection, and the configured TURN relay \
                didn't work either. Check that both devices have network access.
                """
            }
            return """
            Couldn't open a direct connection between the two devices. STUN alone \
            only works when both devices can reach each other directly - put them \
            on the same Wi-Fi network, or configure a TURN relay.
            """
        case .connectionLost:
            return "The connection dropped. Trying to recover it."
        case .peerLeft(let deviceName):
            return "\(deviceName) left the session."
        case .mediaNeverArrived:
            return """
            Connected, but no video arrived from the camera device. Check that it \
            is still on the Camera Mode screen with the preview showing.
            """
        case .snapshotTransferFailed(let reason):
            return "The photo couldn't be transferred: \(reason)"
        case .signalingUnavailable(let reason):
            // `reason` is built by `FirestoreFailure.remoteCameraError`, which
            // already names the operation and path and - only for an actual
            // permission denial - points at the undeployed rules. Repeating
            // that hint here would attach it to network failures too, sending
            // people to the Firebase console to fix something that isn't
            // broken.
            return "Couldn't reach the signaling service: \(reason)"
        }
    }

    /// Whether retrying the same action could plausibly work.
    var isRecoverable: Bool {
        switch self {
        case .cameraPermissionDenied, .cameraUnavailable, .notAuthenticated:
            return false
        case .noCameraDevicesFound, .sessionNotAddressedToThisDevice, .sessionExpired,
             .iceNegotiationFailed, .connectionLost, .peerLeft, .mediaNeverArrived,
             .snapshotTransferFailed, .signalingUnavailable:
            return true
        }
    }
}
