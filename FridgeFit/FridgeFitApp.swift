//
//  FridgeFitApp.swift
//  FridgeFit
//
//  Created by Kai-Hsiang on 9/9/2026.
//

import SwiftUI
import FirebaseCore
import GoogleSignIn
import UIKit

@main
struct FridgeFitApp: App {
    @StateObject private var authViewModel = AuthViewModel()

    init() {
        FirebaseApp.configure()
        if UITestSupport.isEnabled {
            // no point waiting on animations in UI tests, it just makes them slow and flaky
            UIView.setAnimationsEnabled(false)
        }
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if UITestSupport.isEnabled {
                    // skip login entirely, UI tests run against in-memory data
                    ContentView(dependencies: .uiTesting())
                } else if authViewModel.isAuthenticated {
                    ContentView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(authViewModel)
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
