//
//  RecipeListView.swift
//  FridgeFit
//

import SwiftUI

/// Lets the signed-in user browse recipes and see, at a glance, whether
/// their current pantry can make each one.
struct RecipeListView: View {
    @ObservedObject var viewModel: RecipeViewModel
    @ObservedObject var substitutionViewModel: SubstitutionViewModel
    @ObservedObject var suggestionViewModel: RecipeSuggestionViewModel
    /// Kept shared with the Recipes tab's recommendation root so catalogue
    /// navigation never creates a second recommendation session.
    @ObservedObject var recommendationViewModel: RecommendationViewModel
    @State private var isPresentingPantryIdeas = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.section) {
                RecipeCatalogueHeader(
                    recipeCount: viewModel.recipes.count,
                    onOpenPantryIdeas: { isPresentingPantryIdeas = true }
                )

                if viewModel.isLoading && viewModel.recipes.isEmpty {
                    RecipeCatalogueLoadingState()
                } else if viewModel.recipes.isEmpty {
                    RecipeCatalogueEmptyState(
                        hasLoadError: viewModel.errorMessage != nil,
                        onRetry: { Task { await viewModel.loadRecipes() } }
                    )
                } else {
                    if !viewModel.savedRecipes.isEmpty {
                        RecipeCatalogueSection(
                            title: "Saved from Discover",
                            subtitle: "Your saved recipes, checked against today's pantry",
                            systemImage: "bookmark.fill",
                            recipes: viewModel.savedRecipes,
                            viewModel: viewModel,
                            substitutionViewModel: substitutionViewModel,
                            footer: "Recipe data via Spoonacular. Use the Saved menu on a card to remove it.",
                            onRemove: { recipe in
                                Task { await viewModel.removeSavedRecipe(recipe) }
                            }
                        )
                    }

                    RecipeCatalogueSection(
                        title: "FridgeFit Recipes",
                        subtitle: "Reliable recipes from the built-in collection",
                        systemImage: "leaf.fill",
                        recipes: viewModel.bundledRecipes,
                        viewModel: viewModel,
                        substitutionViewModel: substitutionViewModel
                    )
                }
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.top, FridgeFitTheme.Spacing.small)
            .padding(.bottom, FridgeFitTheme.Spacing.screen)
        }
        .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refreshFeasibility() }
        .onAppear {
            Task { await viewModel.loadRecipes() }
        }
        .sheet(isPresented: $isPresentingPantryIdeas) {
            PantryRecipeIdeasView(viewModel: suggestionViewModel)
        }
        .alert(
            "Couldn't Load Recipes",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in
                    if !isPresented { viewModel.errorMessage = nil }
                }
            )
        ) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        // Saved-recipe problems are reported separately so a Firestore
        // failure never shows up as "Couldn't Load Recipes". Gated on
        // `errorMessage == nil` to give the two alerts a deterministic
        // precedence rather than letting both bindings go true at once.
        .alert(
            "Saved Recipes",
            isPresented: Binding(
                get: { viewModel.savedRecipeErrorMessage != nil && viewModel.errorMessage == nil },
                set: { isPresented in
                    if !isPresented { viewModel.savedRecipeErrorMessage = nil }
                }
            )
        ) {
            Button("OK") { viewModel.savedRecipeErrorMessage = nil }
        } message: {
            Text(viewModel.savedRecipeErrorMessage ?? "")
        }
    }

}

private struct RecipeCatalogueHeader: View {
    let recipeCount: Int
    let onOpenPantryIdeas: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            Text("Browse All Recipes")
                .font(FridgeFitTheme.Typography.hero)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            Text("Explore the full collection and see how every recipe matches your kitchen.")
                .font(FridgeFitTheme.Typography.body)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: FridgeFitTheme.Spacing.small) {
                    FridgeFitStatusBadge(
                        title: "\(recipeCount) recipes",
                        systemImage: "books.vertical.fill",
                        tone: .success
                    )
                    pantryIdeasButton
                }
                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
                    FridgeFitStatusBadge(
                        title: "\(recipeCount) recipes",
                        systemImage: "books.vertical.fill",
                        tone: .success
                    )
                    pantryIdeasButton
                }
            }
        }
    }

    private var pantryIdeasButton: some View {
        Button(action: onOpenPantryIdeas) {
            Label("Pantry Ideas", systemImage: "lightbulb.fill")
        }
        .buttonStyle(FridgeFitSecondaryButtonStyle())
    }
}

private struct RecipeCatalogueSection: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let recipes: [Recipe]
    @ObservedObject var viewModel: RecipeViewModel
    @ObservedObject var substitutionViewModel: SubstitutionViewModel
    let footer: LocalizedStringKey?
    var onRemove: ((Recipe) -> Void)?

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        systemImage: String,
        recipes: [Recipe],
        viewModel: RecipeViewModel,
        substitutionViewModel: SubstitutionViewModel,
        footer: LocalizedStringKey? = nil,
        onRemove: ((Recipe) -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.recipes = recipes
        self.viewModel = viewModel
        self.substitutionViewModel = substitutionViewModel
        self.footer = footer
        self.onRemove = onRemove
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
                Image(systemName: systemImage)
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                    .frame(width: 28, height: 28)
                    .background(FridgeFitTheme.ColorToken.successBackground, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(FridgeFitTheme.Typography.screenTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    Text(subtitle)
                        .font(FridgeFitTheme.Typography.metadata)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                }
                Spacer(minLength: FridgeFitTheme.Spacing.small)
                Text(recipes.count, format: .number)
                    .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .padding(.horizontal, FridgeFitTheme.Spacing.small)
                    .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
                    .background(FridgeFitTheme.ColorToken.disabledSurface, in: Capsule())
            }

            ForEach(recipes) { recipe in
                RecipeCatalogueCard(
                    recipe: recipe,
                    feasibility: viewModel.feasibility(for: recipe),
                    isSaved: onRemove != nil,
                    viewModel: viewModel,
                    substitutionViewModel: substitutionViewModel,
                    onRemove: onRemove.map { action in { action(recipe) } }
                )
            }

            if let footer {
                Text(footer)
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .padding(.horizontal, FridgeFitTheme.Spacing.xSmall)
            }
        }
    }
}

private struct RecipeCatalogueCard: View {
    let recipe: Recipe
    let feasibility: RecipeFeasibilityResult?
    let isSaved: Bool
    @ObservedObject var viewModel: RecipeViewModel
    @ObservedObject var substitutionViewModel: SubstitutionViewModel
    let onRemove: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            RecipeRow(recipe: recipe, feasibility: feasibility, isSaved: isSaved)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: FridgeFitTheme.Spacing.small) {
                    if let onRemove {
                        removeMenu(action: onRemove)
                    }
                    detailLink
                }
                VStack(spacing: FridgeFitTheme.Spacing.small) {
                    detailLink
                    if let onRemove {
                        removeMenu(action: onRemove)
                    }
                }
            }
        }
        .padding(FridgeFitTheme.Spacing.large)
        .fridgeFitCardSurface()
    }

    private var detailLink: some View {
        NavigationLink {
            RecipeDetailView(
                recipe: recipe,
                viewModel: viewModel,
                substitutionViewModel: substitutionViewModel
            )
        } label: {
            Label("View Recipe", systemImage: "arrow.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(FridgeFitPrimaryButtonStyle())
    }

    private func removeMenu(action: @escaping () -> Void) -> some View {
        Menu {
            Button(role: .destructive, action: action) {
                Label("Remove Saved Recipe", systemImage: "bookmark.slash")
            }
        } label: {
            Label("Saved", systemImage: "bookmark.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(FridgeFitSecondaryButtonStyle())
        .accessibilityHint("Opens actions for this saved recipe")
    }
}

private struct RecipeCatalogueLoadingState: View {
    var body: some View {
        VStack(spacing: FridgeFitTheme.Spacing.large) {
            ProgressView()
                .controlSize(.large)
                .tint(FridgeFitTheme.ColorToken.primary)
            Text("Checking every recipe against your pantry…")
                .font(FridgeFitTheme.Typography.cardTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(FridgeFitTheme.Spacing.xLarge)
        .frame(maxWidth: .infinity, minHeight: 240)
        .fridgeFitCardSurface()
    }
}

private struct RecipeCatalogueEmptyState: View {
    let hasLoadError: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: FridgeFitTheme.Spacing.large) {
            Image(systemName: hasLoadError ? "exclamationmark.triangle.fill" : "fork.knife")
                .font(.largeTitle)
                .foregroundStyle(hasLoadError ? FridgeFitTheme.ColorToken.danger : FridgeFitTheme.ColorToken.primary)
                .frame(width: 88, height: 88)
                .background(FridgeFitTheme.ColorToken.successBackground, in: Circle())
                .accessibilityHidden(true)
            VStack(spacing: FridgeFitTheme.Spacing.small) {
                Text(hasLoadError ? "Couldn't load recipes" : "No recipes available yet")
                    .font(FridgeFitTheme.Typography.screenTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    .multilineTextAlignment(.center)
                Text(hasLoadError ? "Check your connection and try loading the catalogue again." : "Check back later for recipes to cook.")
                    .font(FridgeFitTheme.Typography.body)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if hasLoadError {
                Button("Try Again", action: onRetry)
                    .buttonStyle(FridgeFitPrimaryButtonStyle())
            }
        }
        .padding(FridgeFitTheme.Spacing.xLarge)
        .frame(maxWidth: .infinity)
        .fridgeFitCardSurface()
    }
}

#Preview {
    let pantry = InMemoryPantryRepository(seedItems: [
        PantryItem(ingredient: Ingredient(name: "Chicken Breast", category: .meat), quantity: 500, unit: .grams),
        PantryItem(ingredient: Ingredient(name: "Pasta", category: .grain), quantity: 500, unit: .grams),
        PantryItem(ingredient: Ingredient(name: "Garlic", category: .produce), quantity: 3, unit: .pieces),
    ])
    let substitutionViewModel = SubstitutionViewModel(
        useCase: GetIngredientSubstitutionsUseCase(
            substitutionService: MockSubstitutionService(),
            pantryRepository: pantry,
            cache: SubstitutionCache()
        )
    )
    let suggestionViewModel = RecipeSuggestionViewModel(
        useCase: SuggestRecipesFromPantryUseCase(
            suggestionService: MockRecipeSuggestionService(),
            pantryRepository: pantry
        )
    )
    let recipes = BundledRecipeRepository()
    NavigationStack {
        RecipeListView(
            viewModel: RecipeViewModel(recipeRepository: recipes, pantryRepository: pantry),
            substitutionViewModel: substitutionViewModel,
            suggestionViewModel: suggestionViewModel,
            recommendationViewModel: RecommendationViewModel(
                generateUseCase: GenerateContextAwareRecommendationsUseCase(
                    recipeRepository: recipes,
                    pantryRepository: pantry
                )
            )
        )
    }
}
