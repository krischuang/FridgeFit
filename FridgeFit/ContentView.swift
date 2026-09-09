//
//  ContentView.swift
//  FridgeFit
//
//  Created by Kai-Hsiang on 9/9/2026.
//

import FirebaseAuth
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "refrigerator")
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
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
