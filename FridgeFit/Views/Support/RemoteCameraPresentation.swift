//
//  RemoteCameraPresentation.swift
//  FridgeFit
//

import SwiftUI

/// Display details for the remote-camera types, kept out of the views the
/// same way `PantryPresentation` and `ScannerPresentation` are.
enum RemoteCameraPresentation {
    static func symbol(for status: DeviceConnectionStatus) -> String {
        switch status {
        case .offline: return "moon.zzz"
        case .available: return "checkmark.circle"
        case .connecting: return "ellipsis.circle"
        case .connected: return "dot.radiowaves.left.and.right"
        case .reconnecting: return "arrow.triangle.2.circlepath"
        case .disconnected: return "xmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    static func tint(for status: DeviceConnectionStatus) -> Color {
        switch status {
        case .offline, .disconnected: return .secondary
        case .available: return .green
        case .connecting, .reconnecting: return .orange
        case .connected: return .accentColor
        case .failed: return .red
        }
    }

    static func symbol(for role: DeviceRole) -> String {
        role == .camera ? "camera" : "iphone.gen3"
    }
}

/// A status word with its matching symbol, used on all three screens so the
/// same state always looks the same.
struct ConnectionStatusLabel: View {
    let status: DeviceConnectionStatus

    var body: some View {
        Label(status.displayName, systemImage: RemoteCameraPresentation.symbol(for: status))
            .foregroundStyle(RemoteCameraPresentation.tint(for: status))
            .font(.subheadline.weight(.medium))
            .accessibilityLabel("Connection status: \(status.displayName)")
    }
}
