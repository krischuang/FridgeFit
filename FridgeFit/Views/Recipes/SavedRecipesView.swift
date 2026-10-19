//
//  SavedRecipesView.swift
//  FridgeFit
//

import SwiftUI

/// The Recipes tab landing screen. It presents only recipes the signed-in
/// user has saved; the bundled catalogue remains a separate destination.
struct SavedRecipesView: View {
    @ObservedObject var viewModel: RecipeViewModel
    @ObservedObject var substitutionViewModel: SubstitutionViewModel
    let onExploreDiscover: () -> Void
    let onFindRecommendations: () -> Void
    let onBrowseAllRecipes: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.section) {
                SavedRecipesHeader(
                    savedCount: viewModel.savedRecipes.count,
                    onExploreDiscover: onExploreDiscover
                )

                SavedRecipesActions(
                    onFindRecommendations: onFindRecommendations,
                    onBrowseAllRecipes: onBrowseAllRecipes
                )

                if viewModel.isLoading && !viewModel.hasLoaded {
                    SavedRecipesLoadingState()
                } else if viewModel.savedRecipes.isEmpty {
                    SavedRecipesEmptyState(
                        hasError: viewModel.savedRecipeErrorMessage != nil,
                        onExploreDiscover: onExploreDiscover,
                        onRetry: { Task { await viewModel.loadRecipes() } }
                    )
                } else {
                    SavedRecipeCollection(
                        recipes: viewModel.savedRecipes,
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
        .refreshable { await viewModel.loadRecipes() }
        .task { await viewModel.loadRecipesIfNeeded() }
        .alert(
            "Saved Recipes",
            isPresented: Binding(
                get: { viewModel.savedRecipeErrorMessage != nil },
                set: { if !$0 { viewModel.savedRecipeErrorMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.savedRecipeErrorMessage = nil }
        } message: {
            Text(viewModel.savedRecipeErrorMessage ?? "")
        }
    }
}

private struct SavedRecipesHeader: View {
    let savedCount: Int
    let onExploreDiscover: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            Text("Saved Recipes")
                .font(FridgeFitTheme.Typography.hero)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            Text("Your recipe collection, checked against the ingredients in your kitchen.")
                .font(FridgeFitTheme.Typography.body)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: FridgeFitTheme.Spacing.small) {
                    FridgeFitStatusBadge(
                        title: "\(savedCount) saved",
                        systemImage: "bookmark.fill",
                        tone: .success
                    )
                    exploreButton
                }
                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
                    FridgeFitStatusBadge(
                        title: "\(savedCount) saved",
                        systemImage: "bookmark.fill",
                        tone: .success
                    )
                    exploreButton
                }
            }
        }
    }

    private var exploreButton: some View {
        Button(action: onExploreDiscover) {
            Label("Explore Discover", systemImage: "globe")
        }
        .buttonStyle(FridgeFitSecondaryButtonStyle())
    }
}

private struct SavedRecipesActions: View {
    let onFindRecommendations: () -> Void
    let onBrowseAllRecipes: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: FridgeFitTheme.Spacing.small) {
                recommendationsButton
                catalogueButton
            }
            VStack(spacing: FridgeFitTheme.Spacing.small) {
                recommendationsButton
                catalogueButton
            }
        }
    }

    private var recommendationsButton: some View {
        Button(action: onFindRecommendations) {
            Label("Find My Recipes", systemImage: "sparkles")
        }
        .buttonStyle(FridgeFitPrimaryButtonStyle())
    }

    private var catalogueButton: some View {
        Button(action: onBrowseAllRecipes) {
            Label("Browse All Recipes", systemImage: "book.closed")
        }
        .buttonStyle(FridgeFitSecondaryButtonStyle())
    }
}

private struct SavedRecipeCollection: View {
    let recipes: [Recipe]
    @ObservedObject var viewModel: RecipeViewModel
    @ObservedObject var substitutionViewModel: SubstitutionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your Collection")
                    .font(FridgeFitTheme.Typography.screenTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Spacer()
                Text(recipes.count, format: .number)
                    .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }

            ForEach(recipes) { recipe in
                RecipeCatalogueCard(
                    recipe: recipe,
                    feasibility: viewModel.feasibility(for: recipe),
                    isSaved: true,
                    viewModel: viewModel,
                    substitutionViewModel: substitutionViewModel,
                    onRemove: { Task { await viewModel.removeSavedRecipe(recipe) } }
                )
            }

            Text("Recipe data for recipes saved from Discover is provided by Spoonacular.")
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        }
    }
}

private struct SavedRecipesLoadingState: View {
    var body: some View {
        VStack(spacing: FridgeFitTheme.Spacing.large) {
            ProgressView()
                .controlSize(.large)
                .tint(FridgeFitTheme.ColorToken.primary)
            Text("Loading your saved recipes…")
                .font(FridgeFitTheme.Typography.cardTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .fridgeFitCardSurface()
    }
}

private struct SavedRecipesEmptyState: View {
    let hasError: Bool
    let onExploreDiscover: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: FridgeFitTheme.Spacing.large) {
            Image(systemName: hasError ? "exclamationmark.triangle.fill" : "bookmark")
                .font(.largeTitle)
                .foregroundStyle(hasError ? FridgeFitTheme.ColorToken.danger : FridgeFitTheme.ColorToken.primary)
                .frame(width: 88, height: 88)
                .background(FridgeFitTheme.ColorToken.successBackground, in: Circle())
                .accessibilityHidden(true)
            VStack(spacing: FridgeFitTheme.Spacing.small) {
                Text(hasError ? "Couldn't load saved recipes" : "Save recipes you love")
                    .font(FridgeFitTheme.Typography.screenTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    .multilineTextAlignment(.center)
                Text(hasError ? "Try loading your collection again." : "Explore Discover and bookmark a recipe to keep it here.")
                    .font(FridgeFitTheme.Typography.body)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button(hasError ? "Try Again" : "Explore Discover", action: hasError ? onRetry : onExploreDiscover)
                .buttonStyle(FridgeFitPrimaryButtonStyle())
        }
        .padding(FridgeFitTheme.Spacing.xLarge)
        .frame(maxWidth: .infinity)
        .fridgeFitCardSurface()
    }
}
