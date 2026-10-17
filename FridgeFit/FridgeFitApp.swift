//
//  FridgeFitApp.swift
//  FridgeFit
//
//  Created by Kai-Hsiang on 9/9/2026.
//

import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct FridgeFitApp: App {
    @StateObject private var authViewModel = AuthViewModel()

    /// The composition root, or the error that stopped it being built.
    ///
    /// Built once here rather than inside `ContentView`, so the repositories
    /// exist before any view does and every screen is handed the same pair.
    private let dependencies: Result<AppDependencies, Error>

    init() {
        FirebaseApp.configure()
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }

        // Opening the local store can fail - a corrupt file, or no room on
        // the device. That is reported, not worked around: see
        // `PersistenceFailureView` for why there is no fallback to Firebase.
        dependencies = Result { try AppDependencies() }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch dependencies {
                case .success(let dependencies):
                    if authViewModel.isAuthenticated {
                        ContentView(dependencies: dependencies)
                    } else {
                        LoginView()
                    }
                case .failure(let error):
                    PersistenceFailureView(error: error)
                }
            }
            .environmentObject(authViewModel)
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}

/// Shown when the local store could not be opened at launch.
///
/// ## Why this does not fall back to Firebase
///
/// Silently switching backend would be the worst available outcome. A user
/// whose local pantry failed to open would be shown an empty cloud pantry
/// instead, and would reasonably conclude that FridgeFit had lost all their
/// food - when in fact it is still on the device, behind a store that did not
/// open. Worse, anything they re-entered would go to the other backend, so
/// the two would diverge with no way to reconcile them.
///
/// So the app says what happened and stops. Nothing is written anywhere.
private struct PersistenceFailureView: View {
    let error: Error

    var body: some View {
        ContentUnavailableView {
            Label("FridgeFit can't open your kitchen", systemImage: "externaldrive.badge.xmark")
        } description: {
            Text("""
            The on-device database didn't open, so FridgeFit has stopped \
            rather than risk saving your food somewhere it won't be found. \
            Your existing data has not been changed.

            Try restarting the app. If that doesn't help, restarting the \
            device usually will.
            """)
        }
        .accessibilityElement(children: .combine)
        // The underlying reason, for a bug report. Not part of the
        // explanation above, which is written for someone who just wants
        // their pantry back.
        .overlay(alignment: .bottom) {
            Text(error.localizedDescription)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding()
                .accessibilityLabel("Technical detail: \(error.localizedDescription)")
        }
    }
}
