//
//  ContentView.swift
//  FridgeFit
//
//  Created by Kai-Hsiang on 9/9/2026.
//

import SwiftUI

/// Root of the authenticated app: Pantry, Recipes, and Profile, each in
/// its own tab with its own navigation stack.
struct ContentView: View {
    @StateObject private var pantryViewModel: PantryViewModel
    @StateObject private var recipeViewModel: RecipeViewModel

    init() {
        let pantryRepository = FirestorePantryRepository()
        _pantryViewModel = StateObject(wrappedValue: PantryViewModel(pantryRepository: pantryRepository))
        _recipeViewModel = StateObject(wrappedValue: RecipeViewModel(pantryRepository: pantryRepository))
    }

    var body: some View {
        TabView {
            NavigationStack {
                PantryView(viewModel: pantryViewModel)
            }
            .tabItem { Label("Pantry", systemImage: "cabinet") }

            NavigationStack {
                RecipeListView(viewModel: recipeViewModel)
            }
            .tabItem { Label("Recipes", systemImage: "fork.knife") }

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
