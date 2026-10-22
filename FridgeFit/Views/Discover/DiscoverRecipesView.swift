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
                // The pantry items this search was ranked around. Shown
                // above the results rather than on each card, because it is
                // a property of the search, not of any one recipe.
                DiscoverUrgentPantryStrip(uses: viewModel.urgentPantryIngredients)
                DiscoverContent(
                    matches: viewModel.matches,
                    isLoading: viewModel.isLoading,
                    hasSearched: viewModel.hasSearched,
                    errorMessage: viewModel.errorMessage,
                    providerUnavailableExplanation: providerUnavailableExplanation,
                    isShowingCachedResults: viewModel.isShowingCachedResults,
                    excludedForSafetyCount: viewModel.excludedForSafetyCount,
                    hiddenRecipeCount: viewModel.hiddenRecipeIDs.count,
                    recipeViewModel: recipeViewModel,
                    expiryUse: { viewModel.expiryUse(for: $0) },
                    onHide: { viewModel.hide($0) },
                    onUnhideAll: { viewModel.unhideAll() },
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
        // Coming back from My Fridge: re-check have/missing against the
        // current pantry locally (no API call, no quota). Coalesced with the
        // tab change that brought us here, so the two cost one pantry read.
        .onAppear { viewModel.discoverDidAppear() }
        .navigationDestination(for: OnlineRecipeMatch.self) { pushed in
            LiveOnlineRecipeDetail(pushed: pushed, viewModel: viewModel, recipeViewModel: recipeViewModel)
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
    let hiddenRecipeCount: Int
    @ObservedObject var recipeViewModel: RecipeViewModel
    let expiryUse: (OnlineRecipeMatch) -> OnlineRecipeExpiryUse
    let onHide: (OnlineRecipeMatch) -> Void
    let onUnhideAll: () -> Void
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
                        isSaved: recipeViewModel.isSaved(onlineRecipeID: match.id),
                        expiryUse: expiryUse(match),
                        onHide: { onHide(match) }
                    )
                }
                if excludedForSafetyCount > 0 {
                    Text("\(excludedForSafetyCount) recipes were hidden because their ingredients did not pass your selected intolerance screen.")
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        .padding(.horizontal, FridgeFitTheme.Spacing.xSmall)
                }
                if hiddenRecipeCount > 0 {
                    DiscoverHiddenRecipesFooter(count: hiddenRecipeCount, onUnhideAll: onUnhideAll)
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
    /// Which near-expiry pantry items this recipe would use up. `.none`
    /// renders nothing, so a card about long-life ingredients stays quiet.
    let expiryUse: OnlineRecipeExpiryUse
    let onHide: () -> Void

    private var pantryMatchPresentation: DiscoverPantryMatchPresentation {
        DiscoverPantryMatchPresentation(
            matchedIngredientCount: match.usedIngredientNames.count,
            missingIngredientCount: match.missedIngredients.count
        )
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
                    DiscoverExpiryNote(use: expiryUse)
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
        .contextMenu {
            Button(role: .destructive, action: onHide) {
                Label("Hide this recipe", systemImage: "eye.slash")
            }
        }
        .accessibilityAction(named: "Hide this recipe", onHide)
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
            title: LocalizedStringKey(pantryMatchPresentation.title),
            systemImage: pantryMatchPresentation.systemImage,
            tone: .neutral
        )
    }
}

/// Turns ingredient counts into honest badge copy. In particular, a recipe
/// with no matches is not described as pantry-matched, while a recipe with no
/// ingredient data is distinguished from a measured zero-percent result.
struct DiscoverPantryMatchPresentation: Equatable {
    enum State: Equatable {
        case unavailable
        case noMatches
        case matched(percentage: Int)
    }

    let state: State

    init(matchedIngredientCount: Int, missingIngredientCount: Int) {
        let matched = max(0, matchedIngredientCount)
        let missing = max(0, missingIngredientCount)
        let total = matched + missing

        guard total > 0 else {
            state = .unavailable
            return
        }
        guard matched > 0 else {
            state = .noMatches
            return
        }

        let percentage = Int((Double(matched) / Double(total) * 100).rounded())
        state = .matched(percentage: percentage)
    }

    var title: String {
        switch state {
        case .unavailable:
            return "Pantry match unavailable"
        case .noMatches:
            return "No pantry matches"
        case .matched(let percentage):
            return "\(percentage)% pantry match"
        }
    }

    var systemImage: String {
        switch state {
        case .unavailable:
            return "questionmark.circle"
        case .noMatches, .matched:
            return "refrigerator.fill"
        }
    }
}

/// The pantry items this search was ranked around, above the results.
///
/// Carried over from the List-based Discover when the screen was redesigned:
/// the ranking still puts recipes that use these first, and without the
/// strip the ordering would look arbitrary.
private struct DiscoverUrgentPantryStrip: View {
    let uses: [UrgentIngredientUse]

    var body: some View {
        if !uses.isEmpty {
            Label(
                "Using up first: \(OnlineRecipeExpiryPresentation.list(uses))",
                systemImage: "clock.badge.exclamationmark"
            )
            .font(FridgeFitTheme.Typography.metadata)
            .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(FridgeFitTheme.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                FridgeFitTheme.ColorToken.warningBackground,
                in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous)
            )
            .accessibilityElement(children: .combine)
        }
    }
}

/// Why a card is ranked where it is: which near-expiry items it uses, and
/// whether any of them have already gone off.
///
/// Expired is deliberately a separate, louder state than urgent. "Uses up
/// your spinach" and "uses spinach that has expired" are different claims,
/// and only one of them is an invitation to cook.
private struct DiscoverExpiryNote: View {
    let use: OnlineRecipeExpiryUse

    var body: some View {
        if use.usesExpiredIngredient {
            Label(
                "Uses \(use.expired.formattedList), which has expired - check it before cooking",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(FridgeFitTheme.Typography.caption)
            .foregroundStyle(FridgeFitTheme.ColorToken.danger)
            .fixedSize(horizontal: false, vertical: true)
        } else if use.usesUrgentIngredient {
            Label(
                "Uses up \(OnlineRecipeExpiryPresentation.list(use.urgent))",
                systemImage: "clock.badge.exclamationmark"
            )
            .font(FridgeFitTheme.Typography.caption)
            .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
            .lineLimit(2)
        }
    }
}

/// The way back from hiding a recipe. Without it, hiding would be a one-way
/// door with no visible record that anything was hidden at all.
private struct DiscoverHiddenRecipesFooter: View {
    let count: Int
    let onUnhideAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
            Button(action: onUnhideAll) {
                Label(
                    count == 1 ? "Show 1 hidden recipe again" : "Show \(count) hidden recipes again",
                    systemImage: "eye"
                )
            }
            .buttonStyle(FridgeFitSecondaryButtonStyle())
            Text("Hidden recipes come back on your next search.")
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .padding(.horizontal, FridgeFitTheme.Spacing.xSmall)
        }
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
                recipeRepository: BundledRecipeRepository(),
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
                recipeRepository: BundledRecipeRepository(),
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

/// The pushed `OnlineRecipeMatch` is a snapshot taken when the row was
/// tapped. This wrapper observes the search view model itself, so an open
/// detail screen shows the latest have/missing after the pantry changes,
/// instead of relying on SwiftUI re-running the destination closure.
///
/// Discover counts as visible while this is pushed - the tab has not
/// changed - so pantry edits keep re-checking and the screen stays live.
/// Falls back to the snapshot if the recipe is no longer in the results
/// (hidden, or filtered out), which is better than an empty screen.
private struct LiveOnlineRecipeDetail: View {
    let pushed: OnlineRecipeMatch
    @ObservedObject var viewModel: OnlineRecipeSearchViewModel
    @ObservedObject var recipeViewModel: RecipeViewModel

    var body: some View {
        let match = viewModel.matches.first { $0.id == pushed.id } ?? pushed
        OnlineRecipeDetailView(
            match: match,
            intolerances: viewModel.preferences.intolerances,
            expiryUse: viewModel.expiryUse(for: match),
            recipeViewModel: recipeViewModel
        )
        .onAppear { viewModel.discoverDidAppear() }
    }
}
