//
//  OnlineRecipeDetailView.swift
//  FridgeFit
//

import SwiftUI

/// Discover's provider-backed detail. It shares the Fresh Botanical structure
/// of `RecipeDetailView`, while clearly retaining the provider's name-only
/// pantry match until the recipe is saved and fully evaluated by FridgeFit.
struct OnlineRecipeDetailView: View {
    let match: OnlineRecipeMatch
    let intolerances: Set<FoodIntolerance>
    /// Which near-expiry pantry items this recipe would use up. Defaulted so
    /// previews and tests that do not care about expiry need not supply it;
    /// `DiscoverRecipesView` always passes the live reading.
    var expiryUse: OnlineRecipeExpiryUse = .none
    @ObservedObject var recipeViewModel: RecipeViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.section) {
                OnlineRecipeDetailHero(match: match)
                OnlineRecipeMatchCard(match: match)
                // Above the save action on purpose: whether this recipe uses
                // up food that is about to go off is the reason to cook it
                // tonight rather than bookmark it for later.
                OnlineRecipeUseItUpCard(use: expiryUse)
                OnlineRecipeSaveCard(recipe: match.recipe, viewModel: recipeViewModel)

                if let summary = match.recipe.summary, !summary.isEmpty {
                    OnlineRecipeAboutCard(summary: summary)
                }

                OnlineAllergenCard(recipe: match.recipe, intolerances: intolerances)
                OnlineIngredientsBreakdown(match: match)
                OnlineInstructionsSection(recipe: match.recipe)
                OnlineRecipeAttribution(recipe: match.recipe)
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.top, FridgeFitTheme.Spacing.small)
            .padding(.bottom, FridgeFitTheme.Spacing.screen)
        }
        .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
        .navigationTitle("Recipe Detail")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { recipeViewModel.savedRecipeErrorMessage = nil }
    }
}

private struct OnlineRecipeDetailHero: View {
    let match: OnlineRecipeMatch

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            ZStack(alignment: .topLeading) {
                OnlineRecipeImage(url: match.recipe.imageURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.largeCard, style: .continuous))
                FridgeFitStatusBadge(title: "Discover pick", systemImage: "leaf.fill", tone: .success)
                    .padding(FridgeFitTheme.Spacing.medium)
            }

            Text(match.recipe.title)
                .font(FridgeFitTheme.Typography.hero)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            FlowLayout(spacing: FridgeFitTheme.Spacing.small) {
                if let minutes = match.recipe.readyInMinutes {
                    OnlineMetadataPill(title: "\(minutes) min", systemImage: "clock")
                }
                if let servings = match.recipe.servings {
                    OnlineMetadataPill(title: "\(servings) servings", systemImage: "person.2.fill")
                }
                if match.isFromCache {
                    OnlineMetadataPill(title: "Earlier result", systemImage: "icloud.slash")
                }
            }

            if !match.recipe.diets.isEmpty {
                Text(match.recipe.diets.map(\.capitalized).formatted())
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
        }
    }
}

private struct OnlineMetadataPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            .padding(.horizontal, FridgeFitTheme.Spacing.medium)
            .padding(.vertical, FridgeFitTheme.Spacing.small)
            .background(FridgeFitTheme.ColorToken.disabledSurface, in: Capsule())
    }
}

private struct OnlineRecipeMatchCard: View {
    let match: OnlineRecipeMatch

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            HStack(spacing: FridgeFitTheme.Spacing.medium) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(FridgeFitTheme.ColorToken.card)
                    .frame(width: 44, height: 44)
                    .background(FridgeFitTheme.ColorToken.primary, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(match.usedIngredientNames.count) pantry ingredients matched")
                        .font(FridgeFitTheme.Typography.sectionTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                    Text("\(match.missedIngredients.count) ingredients still needed")
                        .font(FridgeFitTheme.Typography.metadata)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                }
            }
            Label(
                "This provider match compares ingredient names. Save the recipe for FridgeFit quantity checks and substitutions.",
                systemImage: "info.circle"
            )
            .font(FridgeFitTheme.Typography.caption)
            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        }
        .padding(FridgeFitTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            FridgeFitTheme.ColorToken.successBackground,
            in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.largeCard, style: .continuous)
        )
    }
}

private struct OnlineRecipeSaveCard: View {
    let recipe: OnlineRecipe
    @ObservedObject var viewModel: RecipeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            if viewModel.canSaveRecipes {
                if viewModel.isSaved(onlineRecipeID: recipe.id) {
                    Label("Saved to Recipes", systemImage: "bookmark.fill")
                        .font(FridgeFitTheme.Typography.cardTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                } else {
                    Button {
                        Task { await viewModel.saveOnlineRecipe(recipe) }
                    } label: {
                        HStack {
                            Label("Save to Recipes", systemImage: "bookmark")
                            if viewModel.isSaving(onlineRecipeID: recipe.id) {
                                Spacer()
                                ProgressView().tint(FridgeFitTheme.ColorToken.card)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FridgeFitPrimaryButtonStyle())
                    .disabled(viewModel.isSaving(onlineRecipeID: recipe.id))
                }
            } else if let explanation = viewModel.savedRecipeUnavailableExplanation {
                Label("Saving isn't available yet", systemImage: "bookmark.slash")
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text(explanation)
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }

            if let message = viewModel.savedRecipeErrorMessage {
                Text(message)
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.danger)
            }

            Text("Saved recipes appear in the Recipes tab and use the same pantry and substitution services as bundled recipes.")
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        }
        .padding(FridgeFitTheme.Spacing.large)
        .fridgeFitCardSurface()
    }
}

/// "Use It Up": the near-expiry pantry items this recipe would consume.
///
/// Carried over from the List-based detail screen when Discover was
/// redesigned. Renders nothing when the recipe uses no urgent item, so it
/// never pads the screen with an empty heading.
private struct OnlineRecipeUseItUpCard: View {
    let use: OnlineRecipeExpiryUse

    var body: some View {
        if use.usesUrgentIngredient || use.usesExpiredIngredient {
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
                Label("Use It Up", systemImage: "clock.badge.exclamationmark")
                    .font(FridgeFitTheme.Typography.sectionTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

                ForEach(use.urgent, id: \.ingredientName) { urgent in
                    Label(
                        "\(urgent.ingredientName) expires \(OnlineRecipeExpiryPresentation.whenText(for: urgent))",
                        systemImage: "circle.fill"
                    )
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
                    .imageScale(.small)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if use.usesExpiredIngredient {
                    Label(
                        "\(use.expired.formattedList) in your pantry has expired - check it before cooking.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.danger)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(FridgeFitTheme.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fridgeFitCardSurface()
            .accessibilityElement(children: .combine)
        }
    }
}

private struct OnlineRecipeAboutCard: View {
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Text("About")
                .font(FridgeFitTheme.Typography.sectionTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            Text(summary)
                .font(FridgeFitTheme.Typography.body)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        }
        .padding(FridgeFitTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fridgeFitCardSurface()
    }
}

private struct OnlineAllergenCard: View {
    let recipe: OnlineRecipe
    let intolerances: Set<FoodIntolerance>

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Text("Allergen Screening")
                .font(FridgeFitTheme.Typography.sectionTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            if let contained = recipe.containsIntolerances {
                if contained.isEmpty {
                    Label(
                        "None of the allergens FridgeFit screens for appear in the supplied ingredient names.",
                        systemImage: "magnifyingglass"
                    )
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                } else {
                    Label(
                        "May contain: \(contained.map(\.displayName).sorted().formatted())",
                        systemImage: "exclamationmark.shield"
                    )
                    .foregroundStyle(contained.isDisjoint(with: intolerances) ? FridgeFitTheme.ColorToken.textSecondary : FridgeFitTheme.ColorToken.danger)
                }
            } else {
                Label("FridgeFit couldn't screen the supplied ingredients.", systemImage: "questionmark.diamond")
                    .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
            }
            Text("This is a keyword screen, not an allergy safety check. Always verify packaging and preparation details.")
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        }
        .font(FridgeFitTheme.Typography.supporting)
        .padding(FridgeFitTheme.Spacing.large)
        .fridgeFitCardSurface()
    }
}

private struct OnlineIngredientsBreakdown: View {
    let match: OnlineRecipeMatch

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            Text("Ingredients Breakdown")
                .font(FridgeFitTheme.Typography.screenTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            if !matchedIngredients.isEmpty {
                OnlineIngredientGroup(title: "Matched in pantry", ingredients: matchedIngredients, match: match)
            }
            if !match.missedIngredients.isEmpty {
                OnlineIngredientGroup(title: "Still needed", ingredients: match.missedIngredients, match: match)
            }
        }
    }

    private var matchedIngredients: [OnlineRecipeIngredient] {
        match.recipe.ingredients.filter { !match.isMissing($0) }
    }
}

private struct OnlineIngredientGroup: View {
    let title: LocalizedStringKey
    let ingredients: [OnlineRecipeIngredient]
    let match: OnlineRecipeMatch

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Text(title)
                .font(FridgeFitTheme.Typography.cardTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            ForEach(ingredients) { ingredient in
                let isMissing = match.isMissing(ingredient)
                HStack(spacing: FridgeFitTheme.Spacing.medium) {
                    Image(systemName: isMissing ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isMissing ? FridgeFitTheme.ColorToken.danger : FridgeFitTheme.ColorToken.primary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(OnlineIngredientName.displayName(ingredient.name))
                            .font(FridgeFitTheme.Typography.cardTitle)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                        Text(ingredient.formattedQuantity)
                            .font(FridgeFitTheme.Typography.metadata)
                            .foregroundStyle(ingredient.quantityIsUncertain ? FridgeFitTheme.ColorToken.warningText : FridgeFitTheme.ColorToken.textSecondary)
                    }
                    Spacer()
                    Text(isMissing ? "Missing" : "Matched")
                        .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(isMissing ? FridgeFitTheme.ColorToken.danger : FridgeFitTheme.ColorToken.primary)
                }
                .padding(FridgeFitTheme.Spacing.medium)
                .fridgeFitCardSurface()
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct OnlineInstructionsSection: View {
    let recipe: OnlineRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            Text("Cooking Instructions")
                .font(FridgeFitTheme.Typography.screenTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            if recipe.steps.isEmpty {
                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
                    Text("No step-by-step method is available for this recipe.")
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    if let source = recipe.sourceURL {
                        Link("Open the original recipe", destination: source)
                            .font(FridgeFitTheme.Typography.button)
                            .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                    }
                }
                .padding(FridgeFitTheme.Spacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fridgeFitCardSurface()
            } else {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.medium) {
                        Text(index + 1, format: .number)
                            .font(FridgeFitTheme.Typography.cardTitle)
                            .foregroundStyle(FridgeFitTheme.ColorToken.card)
                            .frame(width: 32, height: 32)
                            .background(FridgeFitTheme.ColorToken.primary, in: Circle())
                        Text(step)
                            .font(FridgeFitTheme.Typography.body)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    }
                    .padding(FridgeFitTheme.Spacing.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fridgeFitCardSurface()
                }
            }
        }
    }
}

private struct OnlineRecipeAttribution: View {
    let recipe: OnlineRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            if let source = recipe.sourceURL {
                Link(destination: source) {
                    Label("Source: \(recipe.sourceName ?? source.host() ?? "original recipe")", systemImage: "safari")
                }
            }
            if let spoonacularURL = URL(string: "https://spoonacular.com/food-api") {
                Link("Recipe data powered by Spoonacular", destination: spoonacularURL)
            }
        }
        .font(FridgeFitTheme.Typography.caption)
        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
    }
}
