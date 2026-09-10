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
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            if let email = authViewModel.user?.email {
                Text("Signed in as \(email)")
            }
            Button("Sign Out", role: .destructive) {
                authViewModel.signOut()
            }
        }
        .padding()
        .navigationTitle("Profile")
    }
}

#Preview {
    NavigationStack {
        ProfileView()
            .environmentObject(AuthViewModel())
    }
}
