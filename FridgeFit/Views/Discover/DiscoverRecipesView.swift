//
//  DiscoverRecipesView.swift
//  FridgeFit
//

import SwiftUI

/// Discover tab: online recipes (Spoonacular) that use what's in the pantry.
///
/// Also shown as the Recipes tab's "Pantry Ideas" sheet (see
/// `PantryRecipeIdeasView`), sharing the same view model so both places
/// show the same results. Never changes bundled recipes or their
/// feasibility.
struct DiscoverRecipesView: View {
    @ObservedObject var viewModel: OnlineRecipeSearchViewModel
    /// Saves recipes to the Recipes page and knows which already are.
    @ObservedObject var recipeViewModel: RecipeViewModel
    var title: String = "Discover"
    /// Search automatically the first time the screen appears. Off for the
    /// Discover tab (every search spends API quota, so it waits for a tap);
    /// on for the Pantry Ideas sheet, where opening it *is* the request.
    var searchesOnAppear: Bool = false
    @State private var isShowingFilters = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Find recipes online that use what's already in your pantry.")
                        .font(.subheadline)
                    Label(viewModel.preferences.summary, systemImage: "line.3.horizontal.decrease.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await viewModel.search() }
                } label: {
                    HStack {
                        Label(viewModel.hasSearched ? "Search Again" : "Find Recipes", systemImage: "magnifyingglass")
                        Spacer()
                        if viewModel.isLoading { ProgressView() }
                    }
                }
                .disabled(viewModel.isLoading)
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
            }

            if viewModel.isShowingCachedResults {
                Section {
                    Label("You're offline - showing results saved from an earlier search. They may be out of date.", systemImage: "icloud.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.matches.isEmpty {
                Section {
                    ForEach(viewModel.matches) { match in
                        NavigationLink(value: match) {
                            OnlineRecipeRow(match: match, isSaved: recipeViewModel.isSaved(onlineRecipeID: match.id))
                        }
                    }
                } header: {
                    Text("\(viewModel.matches.count) recipes")
                } footer: {
                    if viewModel.excludedForSafetyCount > 0 {
                        Text("\(viewModel.excludedForSafetyCount) recipes were hidden because they contain - or couldn't be verified free of - one of your intolerances.")
                    }
                }
            }

            Section {
                Link(destination: URL(string: "https://spoonacular.com/food-api")!) {
                    Text("Recipe data powered by Spoonacular")
                        .font(.footnote)
                }
            }
        }
        .navigationTitle(title)
        .task {
            await recipeViewModel.loadRecipesIfNeeded()
            if searchesOnAppear && !viewModel.hasSearched && !viewModel.isLoading {
                await viewModel.search()
            }
        }
        .navigationDestination(for: OnlineRecipeMatch.self) { match in
            OnlineRecipeDetailView(match: match, intolerances: viewModel.preferences.intolerances, recipeViewModel: recipeViewModel)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingFilters = true
                } label: {
                    Label("Filters", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $isShowingFilters) {
            NavigationStack {
                OnlineRecipePreferencesView(initial: viewModel.preferences) { updated in
                    viewModel.updatePreferences(updated)
                }
            }
        }
    }
}

/// One search result: thumbnail, title, and how it lines up with the pantry.
private struct OnlineRecipeRow: View {
    let match: OnlineRecipeMatch
    let isSaved: Bool

    var body: some View {
        HStack(spacing: 12) {
            OnlineRecipeImage(url: match.recipe.imageURL)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(match.recipe.title)
                        .font(.headline)
                        .lineLimit(2)
                    if isSaved {
                        Image(systemName: "bookmark.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Saved to Recipes")
                    }
                }
                HStack(spacing: 10) {
                    Label("\(match.usedIngredientNames.count) used", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Label(
                        match.missedIngredients.isEmpty ? "Nothing missing" : "\(match.missedIngredients.count) missing",
                        systemImage: match.missedIngredients.isEmpty ? "cart" : "cart.badge.plus"
                    )
                    .foregroundStyle(match.missedIngredients.isEmpty ? Color.green : Color.orange)
                }
                .font(.caption)
                if let minutes = match.recipe.readyInMinutes {
                    Label("\(minutes) min", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Remote recipe photo with a neutral placeholder.
struct OnlineRecipeImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    Color.secondary.opacity(0.15)
                    Image(systemName: "fork.knife")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    let pantry = InMemoryPantryRepository()
    let service = MockOnlineRecipeService(result: .success([]))
    let useCase = FindOnlineRecipesFromPantryUseCase(recipeService: service, pantryRepository: pantry)
    return NavigationStack {
        DiscoverRecipesView(
            viewModel: OnlineRecipeSearchViewModel(useCase: useCase, preferencesStore: InMemoryOnlineRecipePreferencesStore()),
            recipeViewModel: RecipeViewModel(pantryRepository: pantry, savedRecipeRepository: InMemorySavedRecipeRepository())
        )
    }
}
