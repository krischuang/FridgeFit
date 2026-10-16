//
//  DeviceRole.swift
//  FridgeFit
//

import Foundation

/// What a registered device is currently offering to do in a remote-camera
/// session.
///
/// A device isn't permanently one or the other - the user switches role from
/// the Connected Devices screen, which rewrites `deviceRole` on that
/// device's registration document. `controller` is the default because every
/// install starts out as "the phone you're holding".
nonisolated enum DeviceRole: String, Codable, CaseIterable, Sendable {
    /// Streams its camera to another device.
    case camera
    /// Views another device's camera and drives the capture button.
    case controller

    var displayName: String {
        switch self {
        case .camera: return "Camera"
        case .controller: return "Controller"
        }
    }

    var other: DeviceRole {
        self == .camera ? .controller : .camera
    }
}
