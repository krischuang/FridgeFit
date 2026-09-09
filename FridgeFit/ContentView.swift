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
    @StateObject private var pantryViewModel = PantryViewModel(pantryRepository: FirestorePantryRepository())

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "refrigerator")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                if let email = authViewModel.user?.email {
                    Text("Signed in as \(email)")
                }
                NavigationLink {
                    PantryView(viewModel: pantryViewModel)
                } label: {
                    Label("Open Pantry", systemImage: "cabinet")
                }
                .buttonStyle(.borderedProminent)

                Button("Sign Out", role: .destructive) {
                    authViewModel.signOut()
                }
            }
            .padding()
            .navigationTitle("FridgeFit")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
