//
//  FridgeFitApp.swift
//  FridgeFit
//
//  Created by Kai-Hsiang on 9/9/2026.
//

import SwiftUI
import FirebaseCore

@main
struct FridgeFitApp: App {
    @StateObject private var authViewModel = AuthViewModel()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authViewModel.isAuthenticated {
                    ContentView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(authViewModel)
        }
    }
}
