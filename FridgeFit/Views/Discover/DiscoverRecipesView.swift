//
//  DiscoverRecipesView.swift
//  FridgeFit
//

import SwiftUI

/// Discover tab: online recipes that use what's in the pantry.
///
/// Never changes bundled recipes or their feasibility. A recipe from here
/// only becomes a `Recipe` when the user explicitly saves it.
///
/// ## The not-configured state
///
/// While `OnlineRecipeFeature.provider` is `.disabled` this screen is fully
/// navigable and explains, up front, that online search is not set up. The
/// search control is disabled rather than hidden: a visible, disabled
/// control with a reason beside it tells the user the feature exists and is
/// switched off, where an empty screen reads as a bug. Nothing on this
/// screen reaches the network in that state - the injected service is
/// `UnconfiguredOnlineRecipeService`, and the button cannot be tapped to
/// find out.
///
/// Deliberately does **not** own a `NavigationStack`. The tab provides one,
/// and `navigationDestination` below registers on it, so pushing a recipe
/// detail keeps a single navigation bar and a working back button.
struct DiscoverRecipesView: View {
    @ObservedObject var viewModel: OnlineRecipeSearchViewModel
    /// Saves recipes to the Recipes page and knows which already are.
    @ObservedObject var recipeViewModel: RecipeViewModel
    /// Why online search is unavailable, or `nil` when it is enabled.
    /// Injected so tests and previews can render either state.
    var providerUnavailableExplanation: String? = OnlineRecipeFeature.providerUnavailableExplanation()
    @State private var isShowingFilters = false

    private var isProviderAvailable: Bool { providerUnavailableExplanation == nil }

    var body: some View {
        List {
            if let explanation = providerUnavailableExplanation {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Not set up yet", systemImage: "wifi.slash")
                            .font(.subheadline.weight(.semibold))
                        Text(explanation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }

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
                .disabled(viewModel.isLoading || !isProviderAvailable)
            } footer: {
                if !isProviderAvailable {
                    Text("Search is unavailable until a recipe provider is configured.")
                }
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
        .navigationTitle("Discover")
        .task {
            // Loads the Recipes tab's list so the "Saved" badges here are
            // right even before that tab is opened. Reads local/Firestore
            // recipe state only - never the recipe provider.
            await recipeViewModel.loadRecipesIfNeeded()
        }
        .navigationDestination(for: OnlineRecipeMatch.self) { match in
            OnlineRecipeDetailView(
                match: match,
                intolerances: viewModel.preferences.intolerances,
                recipeViewModel: recipeViewModel
            )
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
///
/// `AsyncImage` issues no request for a `nil` URL, which is the only state
/// reachable while the provider is disabled.
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

#Preview("Not configured") {
    let pantry = InMemoryPantryRepository()
    let service = MockOnlineRecipeService(result: .failure(.notConfigured))
    let useCase = FindOnlineRecipesFromPantryUseCase(recipeService: service, pantryRepository: pantry)
    return NavigationStack {
        DiscoverRecipesView(
            viewModel: OnlineRecipeSearchViewModel(useCase: useCase, preferencesStore: InMemoryOnlineRecipePreferencesStore()),
            recipeViewModel: RecipeViewModel(
                pantryRepository: pantry,
                savedRecipeUnavailableExplanation: OnlineRecipeFeature.savedRecipeUnavailableExplanation(
                    state: .disabledPendingRulesDeployment
                )
            ),
            providerUnavailableExplanation: OnlineRecipeFeature.providerUnavailableExplanation(state: .disabled)
        )
    }
}

#Preview("Enabled with mock results") {
    let pantry = InMemoryPantryRepository()
    let service = MockOnlineRecipeService(result: .success([]))
    let useCase = FindOnlineRecipesFromPantryUseCase(recipeService: service, pantryRepository: pantry)
    return NavigationStack {
        DiscoverRecipesView(
            viewModel: OnlineRecipeSearchViewModel(useCase: useCase, preferencesStore: InMemoryOnlineRecipePreferencesStore()),
            recipeViewModel: RecipeViewModel(
                pantryRepository: pantry,
                savedRecipeRepository: InMemorySavedRecipeRepository()
            ),
            providerUnavailableExplanation: nil
        )
    }
}
