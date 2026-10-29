//
//  CameraAccessPrompt.swift
//  FridgeFit
//

import SwiftUI
import UIKit

/// The iOS Settings page for this app.
///
/// Held as a value rather than opened inline so the destination can be
/// asserted in a test. `UIApplication.shared.open` cannot be, and a camera
/// permission that sends the user nowhere is the failure this exists to stop.
enum SystemSettings {
    static var appSettings: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }
}

/// What to tell the user when the camera cannot be used, and whether Settings
/// can do anything about it.
///
/// A denied permission and a missing camera read almost identically to the
/// user and are completely different to act on: one is two taps from being
/// fixed, the other cannot be fixed at all. Offering "Open Settings" on a
/// device with no camera would send someone to look for a switch that is not
/// there, so `offersSettings` is false for that case and the alert falls back
/// to a plain acknowledgement.
struct CameraAccessPrompt: Equatable {
    let title: String
    let message: String
    /// Whether iOS Settings can actually change this state.
    let offersSettings: Bool

    /// `nil` when access was granted, which is the case with nothing to say.
    init?(_ access: CameraAccess) {
        switch access {
        case .granted:
            return nil
        case .denied:
            self.init(
                title: "Camera Access Is Off",
                message: """
                FridgeFit needs camera access to photograph your fridge or a \
                receipt. Turn it on in Settings, or choose a photo from your \
                library instead.
                """,
                offersSettings: true
            )
        case .unavailable:
            self.init(
                title: "No Camera Available",
                message: """
                This device doesn't have a camera available. Choose a photo \
                from your library instead.
                """,
                offersSettings: false
            )
        }
    }

    private init(title: String, message: String, offersSettings: Bool) {
        self.title = title
        self.message = message
        self.offersSettings = offersSettings
    }
}

extension View {
    /// Presents `prompt` as an alert, with a route into Settings when the
    /// state it describes is one Settings can fix.
    func cameraAccessAlert(_ prompt: Binding<CameraAccessPrompt?>) -> some View {
        modifier(CameraAccessAlertModifier(prompt: prompt))
    }
}

private struct CameraAccessAlertModifier: ViewModifier {
    @Binding var prompt: CameraAccessPrompt?

    /// Taken from the environment rather than calling `UIApplication` so a
    /// preview or a test can intercept the destination.
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.alert(
            prompt?.title ?? "",
            isPresented: Binding(
                get: { prompt != nil },
                set: { if !$0 { prompt = nil } }
            ),
            presenting: prompt
        ) { prompt in
            if prompt.offersSettings, let settings = SystemSettings.appSettings {
                Button("Open Settings") { openURL(settings) }
                Button("Not Now", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { prompt in
            Text(prompt.message)
        }
    }
}
