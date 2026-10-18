import SwiftUI

/// Ranked meal recommendations for the current pantry and cooking context.
/// Ranking and filtering remain owned by `RecommendationViewModel`.
struct RecipeRecommendationsView: View {
    @ObservedObject var viewModel: RecommendationViewModel
    @ObservedObject var recipeViewModel: RecipeViewModel
    @ObservedObject var substitutionViewModel: SubstitutionViewModel
    /// Supplied by app navigation so the original catalogue can reuse its
    /// existing pantry-ideas state. Optional only to keep focused previews and
    /// rendering tests lightweight.
    var suggestionViewModel: RecipeSuggestionViewModel? = nil

    @State private var isPresentingPreferences = false
    @State private var reportingRecipe: Recipe?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.section) {
                RecipeRecommendationsHeader(
                    recommendationCount: viewModel.recommendations.count,
                    bestMatchPercentage: viewModel.recommendations.first?.suitability.pantryMatchPercentage,
                    onOpenPreferences: { isPresentingPreferences = true }
                )
                RecommendationContextStrip(
                    context: viewModel.appliedContext ?? viewModel.draftContext,
                    onOpenPreferences: { isPresentingPreferences = true }
                )
                if let suggestionViewModel {
                    NavigationLink {
                        RecipeListView(
                            viewModel: recipeViewModel,
                            substitutionViewModel: substitutionViewModel,
                            suggestionViewModel: suggestionViewModel,
                            recommendationViewModel: viewModel
                        )
                    } label: {
                        Label("Browse All Recipes", systemImage: "books.vertical")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FridgeFitSecondaryButtonStyle())
                }
                RecommendationScreenContent(
                    viewModel: viewModel,
                    recipeViewModel: recipeViewModel,
                    substitutionViewModel: substitutionViewModel,
                    onReport: { reportingRecipe = $0 },
                    onAdjustPreferences: { isPresentingPreferences = true }
                )
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.top, FridgeFitTheme.Spacing.small)
            .padding(.bottom, FridgeFitTheme.Spacing.screen)
        }
        .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
        .task {
            if !viewModel.hasRun {
                await viewModel.generate()
            }
        }
        .onDisappear { viewModel.cancel() }
        .refreshable { await viewModel.regenerate() }
        .sheet(isPresented: $isPresentingPreferences) {
            CookingContextFormView(context: viewModel.draftContext) { updated in
                viewModel.draftContext = updated
                Task { await viewModel.generate() }
            }
        }
        .confirmationDialog(
            "Why not this one?",
            isPresented: Binding(
                get: { reportingRecipe != nil },
                set: { if !$0 { reportingRecipe = nil } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(SessionRecipeFeedbackReason.allCases) { reason in
                Button(reason.displayText) {
                    if let recipe = reportingRecipe {
                        Task { await viewModel.record(.reported(reason), for: recipe) }
                    }
                    reportingRecipe = nil
                }
            }
            Button("Cancel", role: .cancel) { reportingRecipe = nil }
        }
    }
}

private struct RecipeRecommendationsHeader: View {
    let recommendationCount: Int
    let bestMatchPercentage: Int?
    let onOpenPreferences: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.medium) {
                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                    Text("What can I cook?")
                        .font(FridgeFitTheme.Typography.hero)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    Text("Matched with items inside your kitchen")
                        .font(FridgeFitTheme.Typography.body)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                }
                Spacer(minLength: FridgeFitTheme.Spacing.small)
                Button(action: onOpenPreferences) {
                    Image(systemName: "slider.horizontal.3")
                        .accessibilityLabel("Adjust cooking preferences")
                }
                .buttonStyle(FridgeFitIconButtonStyle())
            }

            if recommendationCount > 0 {
                HStack(spacing: FridgeFitTheme.Spacing.small) {
                    FridgeFitStatusBadge(
                        title: "\(recommendationCount) pantry matches",
                        systemImage: "leaf.fill",
                        tone: .success
                    )
                    if let bestMatchPercentage {
                        FridgeFitStatusBadge(
                            title: "Best \(bestMatchPercentage)% ready",
                            systemImage: "checkmark.circle.fill",
                            tone: .neutral
                        )
                    }
                }
            }
        }
    }
}

private struct RecommendationContextStrip: View {
    let context: CookingContext
    let onOpenPreferences: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: FridgeFitTheme.Spacing.small) {
                RecommendationContextButton(
                    title: context.prioritisesExpiringIngredients ? "Low-waste" : "Standard priority",
                    systemImage: "leaf.fill",
                    isSelected: context.prioritisesExpiringIngredients,
                    action: onOpenPreferences
                )
                RecommendationContextButton(
                    title: context.maximumCookingTime.displayName,
                    systemImage: "timer",
                    isSelected: context.maximumCookingTime != .sixtyMinutes,
                    action: onOpenPreferences
                )
                RecommendationContextButton(
                    title: context.maximumDifficulty.displayName,
                    systemImage: "dial.low",
                    isSelected: context.maximumDifficulty != .challenging,
                    action: onOpenPreferences
                )
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Cooking filters")
    }
}

private struct RecommendationContextButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(FridgeFitChipStyle(isSelected: isSelected))
    }
}

private struct RecommendationScreenContent: View {
    @ObservedObject var viewModel: RecommendationViewModel
    @ObservedObject var recipeViewModel: RecipeViewModel
    @ObservedObject var substitutionViewModel: SubstitutionViewModel
    let onReport: (Recipe) -> Void
    let onAdjustPreferences: () -> Void

    var body: some View {
        if viewModel.isLoading && !viewModel.hasRecommendations {
            RecommendationLoadingState()
        } else if viewModel.hasRecommendations {
            RecommendationResults(
                recommendations: viewModel.recommendations,
                recipeViewModel: recipeViewModel,
                substitutionViewModel: substitutionViewModel,
                feedback: { viewModel.feedback(for: $0) },
                onSave: { recipe in Task { await viewModel.record(.saved, for: recipe) } },
                onSkip: { recipe in Task { await viewModel.record(.skipped, for: recipe) } },
                onReport: onReport,
                onClearFeedback: { recipe in Task { await viewModel.clearFeedback(for: recipe) } },
                onStartNewSession: { Task { await viewModel.startNewSession() } },
                hasSessionFeedback: !viewModel.session.recordedFeedback.isEmpty
            )
        } else if let failure = viewModel.failure {
            RecommendationEmptyState(
                title: failure.errorDescription ?? "No recipe matches found yet",
                message: failure.recoverySuggestion ?? "Try adding ingredients or adjusting your cooking preferences.",
                primaryTitle: primaryActionTitle(for: failure),
                primarySystemImage: primaryActionImage(for: failure),
                onPrimaryAction: { performRecovery(for: failure) },
                onAdjustPreferences: onAdjustPreferences
            )
        } else if let message = viewModel.unexpectedErrorMessage {
            RecommendationErrorState(message: message) {
                Task { await viewModel.regenerate() }
            }
        } else {
            RecommendationEmptyState(
                title: "No recipe matches found yet",
                message: "Generate meal ideas ranked against what's in your pantry right now.",
                primaryTitle: "Find pantry matches",
                primarySystemImage: "sparkles",
                onPrimaryAction: { Task { await viewModel.generate() } },
                onAdjustPreferences: onAdjustPreferences
            )
        }
    }

    private func primaryActionTitle(for failure: RecommendationGenerationError) -> String {
        if failure.isResolvedByAdjustingPreferences { return "Adjust preferences" }
        if failure == .everyRecipeSkippedInSession { return "Start a new session" }
        return "Try again"
    }

    private func primaryActionImage(for failure: RecommendationGenerationError) -> String {
        if failure.isResolvedByAdjustingPreferences { return "slider.horizontal.3" }
        if failure == .everyRecipeSkippedInSession { return "arrow.counterclockwise" }
        return "arrow.clockwise"
    }

    private func performRecovery(for failure: RecommendationGenerationError) {
        if failure.isResolvedByAdjustingPreferences {
            onAdjustPreferences()
        } else if failure == .everyRecipeSkippedInSession {
            Task { await viewModel.startNewSession() }
        } else {
            Task { await viewModel.regenerate() }
        }
    }
}

private struct RecommendationResults: View {
    let recommendations: [RecipeRecommendation]
    @ObservedObject var recipeViewModel: RecipeViewModel
    @ObservedObject var substitutionViewModel: SubstitutionViewModel
    let feedback: (Recipe) -> SessionRecipeFeedbackAction?
    let onSave: (Recipe) -> Void
    let onSkip: (Recipe) -> Void
    let onReport: (Recipe) -> Void
    let onClearFeedback: (Recipe) -> Void
    let onStartNewSession: () -> Void
    let hasSessionFeedback: Bool

    var body: some View {
        let ready = recommendations.filter { $0.readiness == .readyToCook }
        let almostReady = recommendations.filter { $0.readiness != .readyToCook }

        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.section) {
            if !ready.isEmpty {
                RecommendationRecipeSection(
                    title: "Ready to Cook",
                    subtitle: "Every essential ingredient is ready",
                    tone: .ready,
                    recommendations: ready,
                    recipeViewModel: recipeViewModel,
                    substitutionViewModel: substitutionViewModel,
                    feedback: feedback,
                    onSave: onSave,
                    onSkip: onSkip,
                    onReport: onReport,
                    onClearFeedback: onClearFeedback
                )
            }
            if !almostReady.isEmpty {
                RecommendationRecipeSection(
                    title: "Almost Ready",
                    subtitle: "Check an amount or pick up one or two items",
                    tone: .almostReady,
                    recommendations: almostReady,
                    recipeViewModel: recipeViewModel,
                    substitutionViewModel: substitutionViewModel,
                    feedback: feedback,
                    onSave: onSave,
                    onSkip: onSkip,
                    onReport: onReport,
                    onClearFeedback: onClearFeedback
                )
            }
            if hasSessionFeedback {
                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
                    Text("Recommendation session")
                        .font(FridgeFitTheme.Typography.sectionTitle)
                    Text("Your saves, skips, and feedback affect this session only.")
                        .font(FridgeFitTheme.Typography.metadata)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    Button("Start a new session", action: onStartNewSession)
                        .buttonStyle(FridgeFitSecondaryButtonStyle())
                }
            }
        }
    }
}

private struct RecommendationRecipeSection: View {
    enum Tone { case ready, almostReady }

    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let tone: Tone
    let recommendations: [RecipeRecommendation]
    @ObservedObject var recipeViewModel: RecipeViewModel
    @ObservedObject var substitutionViewModel: SubstitutionViewModel
    let feedback: (Recipe) -> SessionRecipeFeedbackAction?
    let onSave: (Recipe) -> Void
    let onSkip: (Recipe) -> Void
    let onReport: (Recipe) -> Void
    let onClearFeedback: (Recipe) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: FridgeFitTheme.Spacing.small) {
                Circle()
                    .fill(tone == .ready ? FridgeFitTheme.ColorToken.primary : FridgeFitTheme.ColorToken.warningText)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(FridgeFitTheme.Typography.screenTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    Text(subtitle)
                        .font(FridgeFitTheme.Typography.metadata)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                }
            }
            ForEach(recommendations) { recommendation in
                RecipeRecommendationCard(
                    recommendation: recommendation,
                    feedback: feedback(recommendation.recipe),
                    recipeViewModel: recipeViewModel,
                    substitutionViewModel: substitutionViewModel,
                    onSave: { onSave(recommendation.recipe) },
                    onSkip: { onSkip(recommendation.recipe) },
                    onReport: { onReport(recommendation.recipe) },
                    onClearFeedback: { onClearFeedback(recommendation.recipe) }
                )
            }
        }
    }
}

private struct RecipeRecommendationCard: View {
    let recommendation: RecipeRecommendation
    let feedback: SessionRecipeFeedbackAction?
    @ObservedObject var recipeViewModel: RecipeViewModel
    @ObservedObject var substitutionViewModel: SubstitutionViewModel
    let onSave: () -> Void
    let onSkip: () -> Void
    let onReport: () -> Void
    let onClearFeedback: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous)
                    .fill(heroBackground)
                    .frame(minHeight: 164)
                Image(systemName: recommendation.recipe.symbolName ?? "fork.knife")
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                    .accessibilityHidden(true)
                VStack {
                    HStack {
                        if let minutes = recommendation.recipe.totalCookingTimeInMinutes {
                            FridgeFitStatusBadge(title: "\(minutes) min", systemImage: "timer", tone: .neutral)
                        }
                        Spacer()
                        FridgeFitStatusBadge(
                            title: "\(recommendation.suitability.pantryMatchPercentage)% ready",
                            systemImage: recommendation.readiness.symbolName,
                            tone: recommendation.readiness == .readyToCook ? .success : .warning
                        )
                    }
                    Spacer()
                }
                .padding(FridgeFitTheme.Spacing.medium)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(recommendation.recipe.title)
                    .font(FridgeFitTheme.Typography.screenTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Spacer(minLength: FridgeFitTheme.Spacing.small)
                if let feedback { FeedbackBadge(action: feedback) }
            }

            Text(recommendation.recipe.summary)
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .lineLimit(3)

            RecommendationMetadataRow(recipe: recommendation.recipe)
            RecommendationAvailabilityDetails(suitability: recommendation.suitability)

            if !recommendation.rankingReasons.isEmpty {
                FlowLayout(spacing: FridgeFitTheme.Spacing.small) {
                    ForEach(recommendation.rankingReasons, id: \.self) { reason in
                        RecommendationReasonChip(reason: reason)
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: FridgeFitTheme.Spacing.small) {
                    feedbackActions
                    recipeLink
                }
                VStack(spacing: FridgeFitTheme.Spacing.small) {
                    HStack(spacing: FridgeFitTheme.Spacing.small) {
                        feedbackActions
                        Spacer()
                    }
                    recipeLink
                }
            }
        }
        .padding(FridgeFitTheme.Spacing.large)
        .fridgeFitCardSurface()
    }

    private var heroBackground: Color {
        recommendation.readiness == .readyToCook
            ? FridgeFitTheme.ColorToken.successBackground
            : FridgeFitTheme.ColorToken.warningBackground
    }

    private var feedbackActions: some View {
        Group {
            Button(action: onSave) {
                Image(systemName: feedback == .saved ? "bookmark.fill" : "bookmark")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(FridgeFitIconButtonStyle())
            .accessibilityLabel(feedback == .saved ? "Saved this session" : "Save this session")

            Menu {
                Button(action: onSkip) { Label("Skip", systemImage: "eye.slash") }
                Button(action: onReport) { Label("Not for me", systemImage: "hand.thumbsdown") }
                if feedback != nil {
                    Button(action: onClearFeedback) {
                        Label("Clear feedback", systemImage: "arrow.uturn.backward")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(FridgeFitIconButtonStyle())
            .accessibilityLabel("More recommendation actions")
        }
    }

    private var recipeLink: some View {
        NavigationLink {
            RecipeDetailView(
                recipe: recommendation.recipe,
                viewModel: recipeViewModel,
                substitutionViewModel: substitutionViewModel
            )
        } label: {
            Text(recommendation.readiness == .readyToCook ? "Cook This Now" : "View Recipe")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(FridgeFitPrimaryButtonStyle())
    }
}

private struct RecommendationAvailabilityDetails: View {
    let suitability: RecipeSuitability

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            if !suitability.shoppingIngredients.isEmpty {
                Label("Still need \(suitability.shoppingIngredients.formattedList)", systemImage: "cart")
                    .foregroundStyle(FridgeFitTheme.ColorToken.danger)
                    .backgroundDetail(FridgeFitTheme.ColorToken.accent.opacity(0.14))
            }
            if !suitability.unverifiedIngredients.isEmpty {
                Label("Check your amount of \(suitability.unverifiedIngredients.formattedList)", systemImage: "questionmark.circle")
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
            if let urgent = suitability.urgentIngredients.first {
                Label("Uses \(urgent.ingredientName) \(expiryPhrase(days: urgent.daysUntilExpiry))", systemImage: "clock.badge.exclamationmark.fill")
                    .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
                    .backgroundDetail(FridgeFitTheme.ColorToken.warningBackground)
            }
            if suitability.usesExpiredIngredient {
                Label("Replace expired \(suitability.expiredIngredients.formattedList) before cooking", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(FridgeFitTheme.ColorToken.danger)
            }
        }
        .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
    }

    private func expiryPhrase(days: Int?) -> String {
        switch days {
        case 0: return "expiring today"
        case 1: return "expiring tomorrow"
        case .some(let days): return "expiring in \(days) days"
        case nil: return "soon"
        }
    }
}

private extension View {
    func backgroundDetail(_ color: Color) -> some View {
        padding(FridgeFitTheme.Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small))
    }
}

private struct RecommendationMetadataRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: FridgeFitTheme.Spacing.medium) {
            if let difficulty = recipe.difficulty { Label(difficulty.displayName, systemImage: "dial.low") }
            if let cuisine = recipe.cuisine { Label(cuisine.displayName, systemImage: "globe") }
            if let servings = recipe.servings { Label("\(servings) servings", systemImage: "person.2") }
        }
        .font(FridgeFitTheme.Typography.caption)
        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        .accessibilityElement(children: .combine)
    }
}

private struct RecommendationLoadingState: View {
    var body: some View {
        VStack(spacing: FridgeFitTheme.Spacing.large) {
            ProgressView().controlSize(.large)
            Text("Looking at your pantry…")
                .font(FridgeFitTheme.Typography.cardTitle)
            Text("Checking quantities, expiry dates, and your cooking preferences.")
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(FridgeFitTheme.Spacing.screen)
        .frame(maxWidth: .infinity, minHeight: 300)
        .fridgeFitCardSurface()
    }
}

private struct RecommendationEmptyState: View {
    let title: String
    let message: String
    let primaryTitle: String
    let primarySystemImage: String
    let onPrimaryAction: () -> Void
    let onAdjustPreferences: () -> Void

    var body: some View {
        VStack(spacing: FridgeFitTheme.Spacing.large) {
            Image(systemName: "takeoutbag.and.cup.and.straw")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 104, height: 104)
                .background(FridgeFitTheme.ColorToken.successBackground, in: Circle())
                .accessibilityHidden(true)
            FridgeFitStatusBadge(title: "Pantry check", systemImage: "info.circle", tone: .warning)
            VStack(spacing: FridgeFitTheme.Spacing.small) {
                Text(title)
                    .font(FridgeFitTheme.Typography.screenTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(FridgeFitTheme.Typography.body)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: onPrimaryAction) { Label(primaryTitle, systemImage: primarySystemImage) }
                .buttonStyle(FridgeFitPrimaryButtonStyle())
            Button(action: onAdjustPreferences) { Label("Adjust cooking preferences", systemImage: "slider.horizontal.3") }
                .buttonStyle(FridgeFitSecondaryButtonStyle())
        }
        .padding(FridgeFitTheme.Spacing.xLarge)
        .frame(maxWidth: .infinity)
        .fridgeFitCardSurface()
    }
}

private struct RecommendationErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: FridgeFitTheme.Spacing.large) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.danger)
            Text("Couldn't recommend meals")
                .font(FridgeFitTheme.Typography.screenTitle)
            Text(message)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again", action: onRetry)
                .buttonStyle(FridgeFitPrimaryButtonStyle())
        }
        .padding(FridgeFitTheme.Spacing.xLarge)
        .frame(maxWidth: .infinity)
        .fridgeFitCardSurface()
    }
}

#Preview {
    let pantry = InMemoryPantryRepository(seedItems: [
        PantryItem(ingredient: Ingredient(name: "Rice", category: .grain), quantity: 600, unit: .grams),
        PantryItem(ingredient: Ingredient(name: "Black Beans", category: .other), quantity: 500, unit: .grams),
        PantryItem(ingredient: Ingredient(name: "Garlic", category: .produce), quantity: 4, unit: .pieces),
    ])
    let recipes = BundledRecipeRepository()
    NavigationStack {
        RecipeRecommendationsView(
            viewModel: RecommendationViewModel(
                generateUseCase: GenerateContextAwareRecommendationsUseCase(
                    recipeRepository: recipes,
                    pantryRepository: pantry
                )
            ),
            recipeViewModel: RecipeViewModel(recipeRepository: recipes, pantryRepository: pantry),
            substitutionViewModel: SubstitutionViewModel(
                useCase: GetIngredientSubstitutionsUseCase(
                    substitutionService: MockSubstitutionService(),
                    pantryRepository: pantry,
                    cache: SubstitutionCache()
                )
            ),
            suggestionViewModel: RecipeSuggestionViewModel(
                useCase: SuggestRecipesFromPantryUseCase(
                    suggestionService: MockRecipeSuggestionService(),
                    pantryRepository: pantry
                )
            )
        )
    }
}
