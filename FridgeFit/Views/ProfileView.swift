//
//  ProfileView.swift
//  FridgeFit
//

import FirebaseAuth
import SwiftUI

/// The signed-in user's account screen - just who's signed in and a way
/// to sign out. Extracted out of `ContentView` when Recipes/Pantry moved
/// into their own tabs.
struct ProfileView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(.tint)
                    if let email = authViewModel.user?.email {
                        Text("Signed in as \(email)")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // Entry point for the remote-camera prototype. Lives here rather
            // than as a fourth tab so Pantry and Recipes are untouched.
            Section {
                NavigationLink {
                    ConnectedDevicesView(identity: DeviceIdentity.current())
                } label: {
                    Label("Connected Devices", systemImage: "iphone.gen3.radiowaves.left.and.right")
                }
            } footer: {
                Text("""
                Use a second iPhone signed into this account as a remote fridge \
                camera.
                """)
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    authViewModel.signOut()
                }
            }
        }
        .navigationTitle("Profile")
    }
}

#Preview {
    NavigationStack {
        ProfileView()
            .environmentObject(AuthViewModel())
    }
}
