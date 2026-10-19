//
//  DiscoverRecipesView.swift
//  FridgeFit
//

import SwiftUI

/// Online recipes matched against the current pantry and supported filters.
/// The containing Discover tab owns the only `NavigationStack`.
struct DiscoverRecipesView: View {
    @ObservedObject var viewModel: OnlineRecipeSearchViewModel
    @ObservedObject var recipeViewModel: RecipeViewModel
    var providerUnavailableExplanation: String? = OnlineRecipeFeature.providerUnavailableExplanation()

    @State private var isShowingFilters = false

    private var isProviderAvailable: Bool { providerUnavailableExplanation == nil }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.section) {
                DiscoverHeader(
                    isLoading: viewModel.isLoading,
                    isRefreshEnabled: isProviderAvailable,
                    onRefresh: refresh,
                    onOpenFilters: { isShowingFilters = true }
                )
                DiscoverFilterStrip(
                    preferences: viewModel.preferences,
                    onOpenFilters: { isShowingFilters = true }
                )
                DiscoverContent(
                    matches: viewModel.matches,
                    isLoading: viewModel.isLoading,
                    hasSearched: viewModel.hasSearched,
                    errorMessage: viewModel.errorMessage,
                    providerUnavailableExplanation: providerUnavailableExplanation,
                    isShowingCachedResults: viewModel.isShowingCachedResults,
                    excludedForSafetyCount: viewModel.excludedForSafetyCount,
                    recipeViewModel: recipeViewModel,
                    onRetry: refresh,
                    onOpenFilters: { isShowingFilters = true }
                )
                DiscoverAttribution()
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.top, FridgeFitTheme.Spacing.small)
            .padding(.bottom, FridgeFitTheme.Spacing.screen)
        }
        .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await recipeViewModel.loadRecipesIfNeeded() }
        .navigationDestination(for: OnlineRecipeMatch.self) { match in
            OnlineRecipeDetailView(
                match: match,
                intolerances: viewModel.preferences.intolerances,
                recipeViewModel: recipeViewModel
            )
        }
        .sheet(isPresented: $isShowingFilters) {
            NavigationStack {
                OnlineRecipePreferencesView(initial: viewModel.preferences) { updated in
                    Task { await viewModel.applyPreferencesAndSearch(updated) }
                }
            }
        }
    }

    private func refresh() {
        guard isProviderAvailable, !viewModel.isLoading else { return }
        Task { await viewModel.search() }
    }
}

private struct DiscoverHeader: View {
    let isLoading: Bool
    let isRefreshEnabled: Bool
    let onRefresh: () -> Void
    let onOpenFilters: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
                    DiscoverHeaderTitle()
                    DiscoverHeaderActions(
                        isLoading: isLoading,
                        isRefreshEnabled: isRefreshEnabled,
                        onRefresh: onRefresh,
                        onOpenFilters: onOpenFilters
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.medium) {
                    DiscoverHeaderTitle()
                    Spacer(minLength: FridgeFitTheme.Spacing.xSmall)
                    DiscoverHeaderActions(
                        isLoading: isLoading,
                        isRefreshEnabled: isRefreshEnabled,
                        onRefresh: onRefresh,
                        onOpenFilters: onOpenFilters
                    )
                }
            }
        }
    }
}

private struct DiscoverHeaderTitle: View {
    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
            Text("Discover")
                .font(FridgeFitTheme.Typography.hero)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            Text("Fresh ideas matched with ingredients in your kitchen")
                .font(FridgeFitTheme.Typography.body)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        }
    }
}

private struct DiscoverHeaderActions: View {
    let isLoading: Bool
    let isRefreshEnabled: Bool
    let onRefresh: () -> Void
    let onOpenFilters: () -> Void

    var body: some View {
        HStack(spacing: FridgeFitTheme.Spacing.small) {
            Button(action: onRefresh) {
                ZStack {
                    Image(systemName: "arrow.clockwise")
                        .opacity(isLoading ? 0 : 1)
                    if isLoading {
                        ProgressView()
                            .tint(FridgeFitTheme.ColorToken.primary)
                    }
                }
            }
            .buttonStyle(FridgeFitIconButtonStyle())
            .disabled(isLoading || !isRefreshEnabled)
            .accessibilityLabel("Find new recipes")

            Button(action: onOpenFilters) {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(FridgeFitIconButtonStyle())
            .accessibilityLabel("Filter recipes")
        }
    }
}

private struct DiscoverFilterStrip: View {
    let preferences: OnlineRecipePreferences
    let onOpenFilters: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: FridgeFitTheme.Spacing.small) {
                DiscoverFilterChip(title: "My ingredients", systemImage: "refrigerator.fill", action: onOpenFilters)
                if preferences.diet != .none {
                    DiscoverFilterChip(title: preferences.diet.displayName, systemImage: "leaf.fill", action: onOpenFilters)
                }
                if let minutes = preferences.maxReadyTimeMinutes {
                    DiscoverFilterChip(title: "Up to \(minutes) min", systemImage: "timer", action: onOpenFilters)
                }
                if !preferences.intolerances.isEmpty {
                    DiscoverFilterChip(
                        title: "Avoid \(preferences.intolerances.count)",
                        systemImage: "checkmark.shield.fill",
                        action: onOpenFilters
                    )
                }
                if preferences == .default {
                    DiscoverFilterChip(title: "Add filters", systemImage: "plus", isSelected: false, action: onOpenFilters)
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Active recipe filters")
    }
}

private struct DiscoverFilterChip: View {
    let title: String
    let systemImage: String
    var isSelected = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(FridgeFitChipStyle(isSelected: isSelected))
    }
}

private struct DiscoverContent: View {
    let matches: [OnlineRecipeMatch]
    let isLoading: Bool
    let hasSearched: Bool
    let errorMessage: String?
    let providerUnavailableExplanation: String?
    let isShowingCachedResults: Bool
    let excludedForSafetyCount: Int
    @ObservedObject var recipeViewModel: RecipeViewModel
    let onRetry: () -> Void
    let onOpenFilters: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            if let providerUnavailableExplanation {
                DiscoverMessageCard(
                    title: "Online recipes need configuration",
                    message: providerUnavailableExplanation,
                    systemImage: "wifi.slash"
                )
            } else if isLoading && matches.isEmpty {
                DiscoverLoadingState()
            } else if let errorMessage {
                DiscoverErrorState(message: errorMessage, onRetry: onRetry, onOpenFilters: onOpenFilters)
            } else if matches.isEmpty {
                DiscoverEmptyState(hasSearched: hasSearched, onOpenFilters: onOpenFilters)
            } else {
                DiscoverResultsHeader(count: matches.count, isLoading: isLoading)
                if isShowingCachedResults {
                    DiscoverMessageCard(
                        title: "Showing saved results",
                        message: "You're offline, so these results may be out of date.",
                        systemImage: "icloud.slash"
                    )
                }
                ForEach(matches) { match in
                    DiscoverRecipeCard(
                        match: match,
                        isSaved: recipeViewModel.isSaved(onlineRecipeID: match.id)
                    )
                }
                if excludedForSafetyCount > 0 {
                    Text("\(excludedForSafetyCount) recipes were hidden because their ingredients did not pass your selected intolerance screen.")
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        .padding(.horizontal, FridgeFitTheme.Spacing.xSmall)
                }
            }
        }
    }
}

private struct DiscoverResultsHeader: View {
    let count: Int
    let isLoading: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fresh matches")
                    .font(FridgeFitTheme.Typography.screenTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text("Sorted by the fewest ingredients still needed")
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
            Spacer()
            if isLoading {
                ProgressView()
                    .tint(FridgeFitTheme.ColorToken.primary)
                    .accessibilityLabel("Refreshing recipes")
            } else {
                Text(count, format: .number)
                    .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .padding(.horizontal, FridgeFitTheme.Spacing.small)
                    .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
                    .background(FridgeFitTheme.ColorToken.disabledSurface, in: Capsule())
            }
        }
    }
}

private struct DiscoverRecipeCard: View {
    let match: OnlineRecipeMatch
    let isSaved: Bool

    private var pantryMatchPercentage: Int {
        let total = match.usedIngredientNames.count + match.missedIngredients.count
        guard total > 0 else { return 0 }
        return Int((Double(match.usedIngredientNames.count) / Double(total) * 100).rounded())
    }

    var body: some View {
        NavigationLink(value: match) {
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
                OnlineRecipeImage(url: match.recipe.imageURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: 176)
                    .clipShape(RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
                    HStack(alignment: .firstTextBaseline, spacing: FridgeFitTheme.Spacing.small) {
                        Text(match.recipe.title)
                            .font(FridgeFitTheme.Typography.cardTitle)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: FridgeFitTheme.Spacing.xSmall)
                        if isSaved {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                                .accessibilityLabel("Saved to Recipes")
                        }
                    }
                    DiscoverRecipeMetadata(recipe: match.recipe)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: FridgeFitTheme.Spacing.small) {
                            readinessBadge
                            pantryBadge
                        }
                        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
                            readinessBadge
                            pantryBadge
                        }
                    }
                    if !match.missedIngredients.isEmpty {
                        Label(
                            "Still need " + match.missedIngredients.prefix(3).map { OnlineIngredientName.displayName($0.name) }.formattedList,
                            systemImage: "cart.badge.plus"
                        )
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
                        .lineLimit(2)
                    }
                    HStack {
                        Text("View recipe")
                            .font(FridgeFitTheme.Typography.button)
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                    .frame(minHeight: 44)
                    .padding(.horizontal, FridgeFitTheme.Spacing.medium)
                    .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
                }
            }
            .padding(FridgeFitTheme.Spacing.large)
            .fridgeFitCardSurface()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens recipe details and saving options")
    }

    private var readinessBadge: some View {
        FridgeFitStatusBadge(
            title: match.missedIngredients.isEmpty ? "Ready to cook" : "\(match.missedIngredients.count) missing",
            systemImage: match.missedIngredients.isEmpty ? "checkmark.circle.fill" : "cart.badge.plus",
            tone: match.missedIngredients.isEmpty ? .success : .warning
        )
    }

    private var pantryBadge: some View {
        FridgeFitStatusBadge(
            title: "\(pantryMatchPercentage)% pantry match",
            systemImage: "refrigerator.fill",
            tone: .neutral
        )
    }
}

private struct DiscoverRecipeMetadata: View {
    let recipe: OnlineRecipe

    var body: some View {
        HStack(spacing: FridgeFitTheme.Spacing.medium) {
            if let minutes = recipe.readyInMinutes {
                Label("\(minutes) min", systemImage: "clock")
            }
            if let servings = recipe.servings {
                Label("\(servings) servings", systemImage: "person.2.fill")
            }
        }
        .font(FridgeFitTheme.Typography.metadata)
        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
    }
}

private struct DiscoverLoadingState: View {
    var body: some View {
        VStack(spacing: FridgeFitTheme.Spacing.large) {
            ProgressView()
                .controlSize(.large)
                .tint(FridgeFitTheme.ColorToken.primary)
            Text("Finding fresh recipes for your kitchen…")
                .font(FridgeFitTheme.Typography.cardTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(FridgeFitTheme.Spacing.xLarge)
        .frame(maxWidth: .infinity, minHeight: 220)
        .fridgeFitCardSurface()
    }
}

private struct DiscoverEmptyState: View {
    let hasSearched: Bool
    let onOpenFilters: () -> Void

    var body: some View {
        VStack(spacing: FridgeFitTheme.Spacing.large) {
            Image(systemName: hasSearched ? "magnifyingglass" : "sparkles")
                .font(.largeTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 88, height: 88)
                .background(FridgeFitTheme.ColorToken.successBackground, in: Circle())
                .accessibilityHidden(true)
            VStack(spacing: FridgeFitTheme.Spacing.small) {
                Text(hasSearched ? "No recipes matched" : "Ready for something new?")
                    .font(FridgeFitTheme.Typography.screenTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    .multilineTextAlignment(.center)
                Text(hasSearched ? "Adjust your filters or refresh to try another search." : "Use the refresh icon above to find recipes based on your current ingredients.")
                    .font(FridgeFitTheme.Typography.body)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if hasSearched {
                Button("Adjust Filters", action: onOpenFilters)
                    .buttonStyle(FridgeFitSecondaryButtonStyle())
            }
        }
        .padding(FridgeFitTheme.Spacing.xLarge)
        .frame(maxWidth: .infinity)
        .fridgeFitCardSurface()
    }
}

private struct DiscoverErrorState: View {
    let message: String
    let onRetry: () -> Void
    let onOpenFilters: () -> Void

    var body: some View {
        VStack(spacing: FridgeFitTheme.Spacing.large) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.danger)
                .accessibilityHidden(true)
            VStack(spacing: FridgeFitTheme.Spacing.small) {
                Text("Couldn't find recipes")
                    .font(FridgeFitTheme.Typography.screenTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text(message)
                    .font(FridgeFitTheme.Typography.body)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .multilineTextAlignment(.center)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: FridgeFitTheme.Spacing.small) {
                    retryButton
                    filterButton
                }
                VStack(spacing: FridgeFitTheme.Spacing.small) {
                    retryButton
                    filterButton
                }
            }
        }
        .padding(FridgeFitTheme.Spacing.xLarge)
        .frame(maxWidth: .infinity)
        .fridgeFitCardSurface()
    }

    private var retryButton: some View {
        Button("Try Again", action: onRetry)
            .buttonStyle(FridgeFitPrimaryButtonStyle())
    }

    private var filterButton: some View {
        Button("Filters", action: onOpenFilters)
            .buttonStyle(FridgeFitSecondaryButtonStyle())
    }
}

private struct DiscoverMessageCard: View {
    let title: LocalizedStringKey
    let message: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.medium) {
            Image(systemName: systemImage)
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 36, height: 36)
                .background(FridgeFitTheme.ColorToken.successBackground, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Text(title)
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text(message)
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
        }
        .padding(FridgeFitTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fridgeFitCardSurface()
        .accessibilityElement(children: .combine)
    }
}

private struct DiscoverAttribution: View {
    var body: some View {
        Link(destination: URL(string: "https://spoonacular.com/food-api")!) {
            Label("Recipe data powered by Spoonacular", systemImage: "info.circle")
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
    }
}

/// Remote recipe photo with a botanical placeholder when no image is usable.
struct OnlineRecipeImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    FridgeFitTheme.ColorToken.successBackground
                    Image(systemName: "leaf.fill")
                        .font(.largeTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.primaryMuted)
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
    DiscoverResultsPreview()
}

@MainActor
private struct DiscoverResultsPreview: View {
    @StateObject private var searchViewModel: OnlineRecipeSearchViewModel
    @StateObject private var recipeViewModel: RecipeViewModel

    init() {
        let pantry = InMemoryPantryRepository(seedItems: [
            PantryItem(
                ingredient: Ingredient(name: "Tomato", category: .produce),
                quantity: 4,
                unit: .pieces
            ),
        ])
        let recipe = OnlineRecipe(
            id: 1,
            title: "Garden Tomato Pasta",
            imageURL: nil,
            readyInMinutes: 25,
            servings: 2,
            summary: "A fresh pantry-friendly pasta.",
            sourceName: "Preview Kitchen",
            sourceURL: nil,
            healthScore: 82,
            diets: ["vegetarian"],
            ingredients: [
                OnlineRecipeIngredient(
                    providerID: 1,
                    name: "Tomato",
                    amount: 4,
                    unit: .pieces,
                    originalUnit: ""
                ),
            ],
            steps: ["Cook and serve."],
            containsIntolerances: []
        )
        let match = OnlineRecipeMatch(
            recipe: recipe,
            usedIngredientNames: ["Tomato"],
            missedIngredients: []
        )
        let service = MockOnlineRecipeService(result: .success([match]))
        _searchViewModel = StateObject(
            wrappedValue: OnlineRecipeSearchViewModel(
                useCase: FindOnlineRecipesFromPantryUseCase(
                    recipeService: service,
                    pantryRepository: pantry
                ),
                preferencesStore: InMemoryOnlineRecipePreferencesStore()
            )
        )
        _recipeViewModel = StateObject(
            wrappedValue: RecipeViewModel(
                pantryRepository: pantry,
                savedRecipeRepository: InMemorySavedRecipeRepository()
            )
        )
    }

    var body: some View {
        NavigationStack {
            DiscoverRecipesView(
                viewModel: searchViewModel,
                recipeViewModel: recipeViewModel,
                providerUnavailableExplanation: nil
            )
        }
        .task {
            if !searchViewModel.hasSearched {
                await searchViewModel.search()
            }
        }
    }
}
