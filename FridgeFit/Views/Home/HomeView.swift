//
//  HomeView.swift
//  FridgeFit
//

import SwiftUI

/// Daily inventory and recipe overview backed by the same stores as My Fridge
/// and Recipes. This view owns presentation state only.
struct HomeView: View {
    @ObservedObject var inventory: InventoryStore
    @ObservedObject var recommendationViewModel: RecommendationViewModel
    @ObservedObject var recipeViewModel: RecipeViewModel
    @ObservedObject var substitutionViewModel: SubstitutionViewModel
    @ObservedObject var suggestionViewModel: RecipeSuggestionViewModel
    @ObservedObject var pantryViewModel: PantryViewModel
    @ObservedObject var scannerViewModel: ReceiptScannerViewModel

    let onOpenMyFridge: () -> Void
    let onOpenSmartScan: () -> Void
    let onBrowseRecipes: () -> Void

    @State private var isPresentingPreferences = false
    @State private var isShowingPantry = false
    @State private var isShowingRecommendations = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.section) {
                HomeBrandHeader()

                if inventory.isLoading && inventory.items.isEmpty {
                    ProgressView("Loading your kitchen…")
                        .frame(maxWidth: .infinity, minHeight: 320)
                } else if inventory.items.isEmpty {
                    HomeEmptyState(onAddIngredient: { isShowingPantry = true })
                    HomeGettingStartedSection(onOpenMyFridge: onOpenMyFridge)
                } else {
                    HomeHeroSection()
                    HomeInventorySummary(
                        freshCount: freshItems.count,
                        expiringItems: expiringItems,
                        onSeeItems: onOpenMyFridge
                    )
                    HomeLifestyleSection(
                        context: recommendationViewModel.draftContext,
                        onCustomize: { isPresentingPreferences = true }
                    )

                    Button {
                        isShowingRecommendations = true
                    } label: {
                        Label(
                            recommendationViewModel.recommendations.isEmpty
                                ? "Find my recipes"
                                : "Find my recipes (\(recommendationViewModel.recommendations.count) available)",
                            systemImage: "sparkles"
                        )
                    }
                    .buttonStyle(FridgeFitPrimaryButtonStyle())

                    if let featuredRecommendation = recommendationViewModel.recommendations.first {
                        HomeFeaturedRecipeSection(
                            recommendation: featuredRecommendation,
                            onOpen: { isShowingRecommendations = true }
                        )
                    } else if recommendationViewModel.isLoading {
                        HomeRecommendationLoadingCard()
                    }

                    HomeQuickActions(
                        onOpenMyFridge: onOpenMyFridge,
                        onOpenSmartScan: onOpenSmartScan,
                        onBrowseRecipes: onBrowseRecipes
                    )
                }

                if let message = inventory.errorMessage {
                    HomeLoadErrorBanner(message: message) {
                        Task { await refresh() }
                    }
                }
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.top, FridgeFitTheme.Spacing.small)
            .padding(.bottom, FridgeFitTheme.Spacing.screen)
        }
        .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await refresh() }
        .task { await refresh() }
        .navigationDestination(isPresented: $isShowingPantry) {
            PantryView(viewModel: pantryViewModel, scannerViewModel: scannerViewModel)
        }
        .navigationDestination(isPresented: $isShowingRecommendations) {
            RecipeRecommendationsView(
                viewModel: recommendationViewModel,
                recipeViewModel: recipeViewModel,
                substitutionViewModel: substitutionViewModel,
                suggestionViewModel: suggestionViewModel
            )
            .toolbar(.visible, for: .navigationBar)
        }
        .sheet(isPresented: $isPresentingPreferences) {
            CookingContextFormView(context: recommendationViewModel.draftContext) { updated in
                recommendationViewModel.draftContext = updated
                Task { await recommendationViewModel.generate() }
            }
        }
    }

    private var expiringItems: [PantryItem] {
        inventory.items.filter { item in
            guard let state = item.expiryState else { return false }
            return state.shouldPrioritise && (state.daysUntilExpiry ?? 0) >= 0
        }
    }

    private var freshItems: [PantryItem] {
        inventory.items.filter { item in
            guard let state = item.expiryState else { return true }
            return !state.shouldPrioritise && (state.daysUntilExpiry ?? 0) >= 0
        }
    }

    private func refresh() async {
        await inventory.load()
        guard !inventory.items.isEmpty else { return }
        if recommendationViewModel.hasRun {
            await recommendationViewModel.regenerate()
        } else {
            await recommendationViewModel.generate()
        }
    }
}

private struct HomeBrandHeader: View {
    var body: some View {
        HStack(spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: "refrigerator")
                .font(.body.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.card)
                .frame(width: 40, height: 40)
                .background(
                    FridgeFitTheme.ColorToken.primary,
                    in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                )

            Text("FridgeFit")
                .font(FridgeFitTheme.Typography.screenTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            Spacer()

            Image(systemName: "leaf.fill")
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("FridgeFit home")
    }
}

private struct HomeHeroSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
            Label("Pantry connected", systemImage: "leaf.fill")
                .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .padding(.horizontal, FridgeFitTheme.Spacing.medium)
                .padding(.vertical, FridgeFitTheme.Spacing.small)
                .background(FridgeFitTheme.ColorToken.successBackground, in: Capsule())

            Text("What's cooking today?")
                .font(FridgeFitTheme.Typography.hero)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            Text("Let's make something great with what's already here.")
                .font(FridgeFitTheme.Typography.body)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        }
    }
}

private struct HomeInventorySummary: View {
    let freshCount: Int
    let expiringItems: [PantryItem]
    let onSeeItems: () -> Void

    var body: some View {
        VStack(spacing: FridgeFitTheme.Spacing.medium) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: FridgeFitTheme.Spacing.medium) {
                    metricCard(value: freshCount, title: "Fresh ingredients", systemImage: "cabinet.fill", tone: .fresh)
                    metricCard(value: expiringItems.count, title: "Expiring soon", systemImage: "clock.fill", tone: .expiring)
                }
                VStack(spacing: FridgeFitTheme.Spacing.medium) {
                    metricCard(value: freshCount, title: "Fresh ingredients", systemImage: "cabinet.fill", tone: .fresh)
                    metricCard(value: expiringItems.count, title: "Expiring soon", systemImage: "clock.fill", tone: .expiring)
                }
            }

            if !expiringItems.isEmpty {
                HStack(spacing: FridgeFitTheme.Spacing.small) {
                    Circle()
                        .fill(FridgeFitTheme.ColorToken.accent)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(expiringItems.prefix(3).map(\.name).formatted())
                            .font(FridgeFitTheme.Typography.cardTitle)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                            .lineLimit(2)
                        Text(expiringItems.first?.expiryState?.title ?? "Use soon")
                            .font(FridgeFitTheme.Typography.caption)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    }

                    Spacer(minLength: FridgeFitTheme.Spacing.small)

                    Button("See items", action: onSeeItems)
                        .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                        .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                        .frame(minHeight: 44)
                }
                .padding(FridgeFitTheme.Spacing.medium)
                .fridgeFitCardSurface()
            }
        }
    }

    private func metricCard(
        value: Int,
        title: LocalizedStringKey,
        systemImage: String,
        tone: HomeMetricCard.Tone
    ) -> some View {
        HomeMetricCard(value: value, title: title, systemImage: systemImage, tone: tone)
    }
}

private struct HomeMetricCard: View {
    enum Tone {
        case fresh
        case expiring
    }

    let value: Int
    let title: LocalizedStringKey
    let systemImage: String
    let tone: Tone

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(foreground)
                .frame(width: 36, height: 36)
                .background(iconBackground, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(value, format: .number)
                    .font(.title.weight(.bold))
                    .foregroundStyle(foreground)
                    .monospacedDigit()
                Text(title)
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(secondaryForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FridgeFitTheme.Spacing.large)
        .background(background, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous)
                .stroke(FridgeFitTheme.ColorToken.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var background: Color {
        tone == .fresh ? FridgeFitTheme.ColorToken.card : FridgeFitTheme.ColorToken.warningBackground
    }

    private var foreground: Color {
        tone == .fresh ? FridgeFitTheme.ColorToken.textPrimary : FridgeFitTheme.ColorToken.warningText
    }

    private var secondaryForeground: Color {
        tone == .fresh ? FridgeFitTheme.ColorToken.textSecondary : FridgeFitTheme.ColorToken.warningText
    }

    private var iconBackground: Color {
        tone == .fresh ? FridgeFitTheme.ColorToken.successBackground : FridgeFitTheme.ColorToken.card.opacity(0.5)
    }
}

private struct HomeLifestyleSection: View {
    let context: CookingContext
    let onCustomize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            HStack {
                Text("Lifestyle match")
                    .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .textCase(.uppercase)
                Spacer()
                Button("Customize", action: onCustomize)
                    .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                    .frame(minHeight: 44)
            }

            ScrollView(.horizontal) {
                HStack(spacing: FridgeFitTheme.Spacing.small) {
                    HomeContextChip(
                        title: context.prioritisesExpiringIngredients ? "Low-waste" : "Standard priority",
                        systemImage: "leaf.fill",
                        isSelected: context.prioritisesExpiringIngredients,
                        action: onCustomize
                    )
                    HomeContextChip(
                        title: context.maximumCookingTime.displayName,
                        systemImage: "timer",
                        isSelected: context.maximumCookingTime != .sixtyMinutes,
                        action: onCustomize
                    )
                    HomeContextChip(
                        title: context.maximumDifficulty.displayName,
                        systemImage: "dial.low",
                        isSelected: context.maximumDifficulty != .challenging,
                        action: onCustomize
                    )
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct HomeContextChip: View {
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

private struct HomeFeaturedRecipeSection: View {
    let recommendation: RecipeRecommendation
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready to Cook")
                        .font(FridgeFitTheme.Typography.screenTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    Text(recommendation.suitability.usesUrgentIngredient
                         ? "Selected based on your expiring ingredients"
                         : "Your strongest pantry match")
                        .font(FridgeFitTheme.Typography.metadata)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                }
                Spacer()
                FridgeFitStatusBadge(title: "Best Match", tone: .success)
            }

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
                ZStack {
                    RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous)
                        .fill(FridgeFitTheme.ColorToken.successBackground)
                        .frame(minHeight: 150)

                    Image(systemName: recommendation.recipe.symbolName ?? "fork.knife")
                        .font(.system(size: 54, weight: .medium))
                        .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                        .accessibilityHidden(true)

                    VStack {
                        HStack {
                            FridgeFitStatusBadge(
                                title: "\(recommendation.suitability.pantryMatchPercentage)% pantry match",
                                systemImage: "checkmark.circle.fill",
                                tone: .success
                            )
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(FridgeFitTheme.Spacing.medium)
                }

                Text(recommendation.recipe.title)
                    .font(FridgeFitTheme.Typography.screenTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

                Text(recommendation.recipe.summary)
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .lineLimit(2)

                if let urgent = recommendation.suitability.urgentIngredients.first {
                    Label(
                        "Uses \(urgent.ingredientName) \(expiryPhrase(days: urgent.daysUntilExpiry))",
                        systemImage: "bolt.fill"
                    )
                    .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
                    .padding(FridgeFitTheme.Spacing.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FridgeFitTheme.ColorToken.warningBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small))
                }

                Button("View recipe", action: onOpen)
                    .buttonStyle(FridgeFitSecondaryButtonStyle())
            }
            .padding(FridgeFitTheme.Spacing.large)
            .fridgeFitCardSurface()
        }
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

private struct HomeRecommendationLoadingCard: View {
    var body: some View {
        HStack(spacing: FridgeFitTheme.Spacing.medium) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text("Finding your best match")
                    .font(FridgeFitTheme.Typography.cardTitle)
                Text("Checking recipes against your current inventory.")
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
        }
        .padding(FridgeFitTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fridgeFitCardSurface()
    }
}

private struct HomeQuickActions: View {
    let onOpenMyFridge: () -> Void
    let onOpenSmartScan: () -> Void
    let onBrowseRecipes: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Text("Quick access")
                .font(FridgeFitTheme.Typography.sectionTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
                HomeQuickAction(title: "My Fridge", systemImage: "refrigerator.fill", action: onOpenMyFridge)
                HomeQuickAction(title: "Smart Scan", systemImage: "viewfinder", action: onOpenSmartScan)
                HomeQuickAction(title: "Browse Recipes", systemImage: "book.closed", action: onBrowseRecipes)
            }
        }
    }
}

private struct HomeQuickAction: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: FridgeFitTheme.Spacing.small) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(FridgeFitTheme.ColorToken.primary)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(FridgeFitTheme.ColorToken.card, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                    .stroke(FridgeFitTheme.ColorToken.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct HomeEmptyState: View {
    let onAddIngredient: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.large) {
            Label("Zero food waste", systemImage: "leaf.fill")
                .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .padding(.horizontal, FridgeFitTheme.Spacing.medium)
                .padding(.vertical, FridgeFitTheme.Spacing.small)
                .background(FridgeFitTheme.ColorToken.successBackground, in: Capsule())

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Text("Welcome Home")
                    .font(FridgeFitTheme.Typography.hero)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text("Let's make something great with what's already here.")
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }

            VStack(spacing: FridgeFitTheme.Spacing.large) {
                Image(systemName: "refrigerator")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                    .frame(width: 132, height: 132)
                    .background(FridgeFitTheme.ColorToken.successBackground, in: Circle())
                    .accessibilityHidden(true)

                VStack(spacing: FridgeFitTheme.Spacing.small) {
                    Text("Welcome to your kitchen companion")
                        .font(FridgeFitTheme.Typography.screenTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("Add a few ingredients from your fridge, freezer, or pantry so FridgeFit can recommend realistic meals.")
                        .font(FridgeFitTheme.Typography.body)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button(action: onAddIngredient) {
                    Label("Add your first ingredient", systemImage: "plus.circle")
                }
                .buttonStyle(FridgeFitPrimaryButtonStyle())
            }
            .padding(FridgeFitTheme.Spacing.xLarge)
            .frame(maxWidth: .infinity)
            .fridgeFitCardSurface()
        }
    }
}

private struct HomeGettingStartedSection: View {
    let onOpenMyFridge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Text("Why start with inventory?")
                .font(FridgeFitTheme.Typography.sectionTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            HomeBenefitRow(
                title: "Reduce waste",
                detail: "Prioritise items approaching expiry so food is easier to use in time.",
                systemImage: "leaf.circle.fill"
            )
            HomeBenefitRow(
                title: "Realistic recipes",
                detail: "See meals assessed against the quantities you actually have.",
                systemImage: "fork.knife.circle.fill"
            )

            Button(action: onOpenMyFridge) {
                Label("Open My Fridge for Smart Scan", systemImage: "viewfinder")
            }
            .buttonStyle(FridgeFitSecondaryButtonStyle())
        }
    }
}

private struct HomeBenefitRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.medium) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 44, height: 44)
                .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text(detail)
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fridgeFitCardSurface()
    }
}

private struct HomeLoadErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Label("Your kitchen couldn't refresh", systemImage: "exclamationmark.triangle.fill")
                .font(FridgeFitTheme.Typography.cardTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.danger)
            Text(message)
                .font(FridgeFitTheme.Typography.metadata)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            Button("Try again", action: onRetry)
                .font(FridgeFitTheme.Typography.button)
                .frame(minHeight: 44)
        }
        .padding(FridgeFitTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fridgeFitCardSurface()
    }
}

private struct HomePreviewContainer: View {
    @StateObject private var inventory: InventoryStore
    @StateObject private var recommendationViewModel: RecommendationViewModel
    @StateObject private var recipeViewModel: RecipeViewModel
    @StateObject private var substitutionViewModel: SubstitutionViewModel
    @StateObject private var suggestionViewModel: RecipeSuggestionViewModel
    @StateObject private var pantryViewModel: PantryViewModel
    @StateObject private var scannerViewModel: ReceiptScannerViewModel

    init(items: [PantryItem]) {
        let pantry = InMemoryPantryRepository(seedItems: items)
        let recipes = BundledRecipeRepository()
        _inventory = StateObject(wrappedValue: InventoryStore(
            pantryRepository: pantry,
            eventRepository: InMemoryInventoryEventRepository()
        ))
        _recommendationViewModel = StateObject(wrappedValue: RecommendationViewModel(
            generateUseCase: GenerateContextAwareRecommendationsUseCase(
                recipeRepository: recipes,
                pantryRepository: pantry
            )
        ))
        _recipeViewModel = StateObject(wrappedValue: RecipeViewModel(
            recipeRepository: recipes,
            pantryRepository: pantry
        ))
        _substitutionViewModel = StateObject(wrappedValue: SubstitutionViewModel(
            useCase: GetIngredientSubstitutionsUseCase(
                substitutionService: MockSubstitutionService(),
                pantryRepository: pantry,
                cache: SubstitutionCache()
            )
        ))
        _suggestionViewModel = StateObject(wrappedValue: RecipeSuggestionViewModel(
            useCase: SuggestRecipesFromPantryUseCase(
                suggestionService: MockRecipeSuggestionService(),
                pantryRepository: pantry
            )
        ))
        _pantryViewModel = StateObject(wrappedValue: PantryViewModel(pantryRepository: pantry))
        _scannerViewModel = StateObject(wrappedValue: ReceiptScannerViewModel(
            textRecognizer: MockReceiptTextRecognizer(lines: []),
            interpreter: MockReceiptIngredientInterpreter(),
            pantryRepository: pantry
        ))
    }

    var body: some View {
        NavigationStack {
            HomeView(
                inventory: inventory,
                recommendationViewModel: recommendationViewModel,
                recipeViewModel: recipeViewModel,
                substitutionViewModel: substitutionViewModel,
                suggestionViewModel: suggestionViewModel,
                pantryViewModel: pantryViewModel,
                scannerViewModel: scannerViewModel,
                onOpenMyFridge: {},
                onOpenSmartScan: {},
                onBrowseRecipes: {}
            )
        }
    }
}

#Preview("Home — Populated") {
    HomePreviewContainer(items: [
        PantryItem(
            ingredient: Ingredient(name: "Spinach", category: .produce),
            quantity: 250,
            unit: .grams,
            expiryDate: .now.addingTimeInterval(86_400)
        ),
        PantryItem(ingredient: Ingredient(name: "Rice", category: .grain), quantity: 600, unit: .grams),
        PantryItem(ingredient: Ingredient(name: "Garlic", category: .produce), quantity: 4, unit: .pieces),
        PantryItem(ingredient: Ingredient(name: "Black Beans", category: .other), quantity: 500, unit: .grams),
    ])
}

#Preview("Home — Empty") {
    HomePreviewContainer(items: [])
}

#Preview("Home — Quick Access") {
    HomeQuickActions(
        onOpenMyFridge: {},
        onOpenSmartScan: {},
        onBrowseRecipes: {}
    )
    .padding(FridgeFitTheme.Spacing.large)
    .background(FridgeFitTheme.ColorToken.canvas)
}
