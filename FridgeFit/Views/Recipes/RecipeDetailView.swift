//
//  RecipeDetailView.swift
//  FridgeFit
//

import SwiftUI
import UIKit

/// Shared detail presentation for bundled, saved, recommended, and featured
/// recipes. Pantry readings remain owned by `RecipeViewModel`.
struct RecipeDetailView: View {
    let recipe: Recipe
    @ObservedObject var viewModel: RecipeViewModel
    @ObservedObject var substitutionViewModel: SubstitutionViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.section) {
                RecipeDetailHero(
                    recipe: recipe,
                    feasibility: viewModel.feasibility(for: recipe),
                    image: viewModel.heroImage(for: recipe)
                )
                RecipePantryMatchCard(feasibility: viewModel.feasibility(for: recipe))

                if let feasibility = viewModel.feasibility(for: recipe),
                   !RecipeDetailSections.unresolvedIngredients(in: feasibility).isEmpty {
                    RecipeFridgeFixPanel(
                        recipe: recipe,
                        feasibility: feasibility,
                        evaluations: RecipeDetailSections.unresolvedIngredients(in: feasibility),
                        viewModel: substitutionViewModel
                    )
                }

                RecipeIngredientsBreakdown(
                    recipe: recipe,
                    feasibility: viewModel.feasibility(for: recipe)
                )
                RecipeInstructionsSection(instructions: recipe.instructions)
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.top, FridgeFitTheme.Spacing.small)
            .padding(.bottom, FridgeFitTheme.Spacing.screen)
        }
        .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
        .navigationTitle("Recipe Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if viewModel.savedRecipeIDs.contains(recipe.id) {
                    Menu {
                        Button(role: .destructive) {
                            Task { await viewModel.removeSavedRecipe(recipe) }
                        } label: {
                            Label("Remove Saved Recipe", systemImage: "bookmark.slash")
                        }
                    } label: {
                        Image(systemName: "bookmark.fill")
                    }
                    .accessibilityLabel("Saved recipe actions")
                }
                ShareLink(item: recipe.title) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share recipe")
            }
        }
        .task { await viewModel.evaluateIfNeeded(recipe) }
        // The list only decodes row-sized thumbnails; the hero wants the full
        // stored photo, and only for the recipe actually open. Cancelled with
        // the view if the user leaves before it finishes.
        .task { await viewModel.loadHeroImage(for: recipe) }
        // Leaving the screen stops any on-device substitution generation
        // still running. Suggestions already found stay in the view model,
        // so coming back doesn't re-run the model.
        .onDisappear { substitutionViewModel.cancelAll() }
    }
}

private struct RecipeDetailHero: View {
    let recipe: Recipe
    let feasibility: RecipeFeasibilityResult?
    /// Decoded stored photo for a saved recipe; falls back to `recipe.imageURL`.
    var image: UIImage? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.largeCard, style: .continuous)
                    .fill(heroBackground)
                    .frame(minHeight: 230)
                if RecipePhoto<EmptyView>.hasPhoto(image: image, imageURL: recipe.imageURL) {
                    Color.clear
                        .frame(height: 230)
                        .frame(maxWidth: .infinity)
                        .overlay {
                            RecipePhoto(image: image, imageURL: recipe.imageURL) {
                                BotanicalRecipeArtwork(symbolName: recipe.symbolName)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.largeCard, style: .continuous))
                        .accessibilityHidden(true)
                } else {
                    BotanicalRecipeArtwork(symbolName: recipe.symbolName)
                }
                VStack {
                    HStack {
                        FridgeFitStatusBadge(title: "Pantry matched", systemImage: "leaf.fill", tone: .success)
                        Spacer()
                    }
                    Spacer()
                    if let feasibility {
                        HStack {
                            Spacer()
                            FridgeFitStatusBadge(
                                title: "\(Int(feasibility.coveragePercentage))% match",
                                systemImage: feasibility.status.symbolName,
                                tone: badgeTone(for: feasibility.status)
                            )
                        }
                    }
                }
                .padding(FridgeFitTheme.Spacing.medium)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Botanical illustration for \(recipe.title)")

            Text(recipe.title)
                .font(FridgeFitTheme.Typography.hero)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            FlowLayout(spacing: FridgeFitTheme.Spacing.small) {
                if let minutes = recipe.totalCookingTimeInMinutes {
                    RecipeMetadataPill(title: "\(minutes) min", systemImage: "clock")
                }
                if let servings = recipe.servings {
                    RecipeMetadataPill(title: "\(servings) servings", systemImage: "person.2.fill")
                }
                if let difficulty = recipe.difficulty {
                    RecipeMetadataPill(title: difficulty.displayName, systemImage: "face.smiling")
                }
            }

            if !recipe.summary.isEmpty {
                Text(recipe.summary)
                    .font(FridgeFitTheme.Typography.body)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
        }
    }

    private var heroBackground: Color {
        switch feasibility?.status {
        case .makeable: FridgeFitTheme.ColorToken.successBackground
        case .almostMakeable: FridgeFitTheme.ColorToken.warningBackground
        case .notMakeable: FridgeFitTheme.ColorToken.accent.opacity(0.14)
        case nil: FridgeFitTheme.ColorToken.disabledSurface
        }
    }
}

private struct BotanicalRecipeArtwork: View {
    let symbolName: String?

    var body: some View {
        ZStack {
            Circle()
                .fill(FridgeFitTheme.ColorToken.card.opacity(0.72))
                .frame(width: 148, height: 148)
            Image(systemName: symbolName ?? "fork.knife")
                .font(.system(size: 62, weight: .medium))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
            Image(systemName: "leaf.fill")
                .font(.title2)
                .foregroundStyle(FridgeFitTheme.ColorToken.primaryMuted)
                .offset(x: 60, y: -54)
            Image(systemName: "leaf.fill")
                .font(.title3)
                .foregroundStyle(FridgeFitTheme.ColorToken.accent.opacity(0.85))
                .rotationEffect(.degrees(160))
                .offset(x: -64, y: 52)
        }
        .accessibilityHidden(true)
    }
}

private struct RecipeMetadataPill: View {
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

private struct RecipePantryMatchCard: View {
    let feasibility: RecipeFeasibilityResult?

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            if let feasibility {
                HStack(alignment: .center, spacing: FridgeFitTheme.Spacing.medium) {
                    Image(systemName: feasibility.status.symbolName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(FridgeFitTheme.ColorToken.card)
                        .frame(width: 44, height: 44)
                        .background(FridgeFitTheme.ColorToken.primary, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(feasibility.matchedCount) of \(feasibility.totalRequiredCount) ingredients ready")
                            .font(FridgeFitTheme.Typography.sectionTitle)
                            .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                        Text(feasibility.status.title)
                            .font(FridgeFitTheme.Typography.metadata)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    }
                    Spacer(minLength: FridgeFitTheme.Spacing.small)
                    Text("\(Int(feasibility.coveragePercentage))%")
                        .font(FridgeFitTheme.Typography.cardTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                        .padding(.horizontal, FridgeFitTheme.Spacing.small)
                        .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
                        .background(FridgeFitTheme.ColorToken.card, in: Capsule())
                }

                if !feasibility.optionalMissingIngredients.isEmpty {
                    Label {
                        if feasibility.optionalMissingIngredients.count == 1 {
                            Text("1 optional ingredient is not in stock")
                        } else {
                            Text("\(feasibility.optionalMissingIngredients.count) optional ingredients are not in stock")
                        }
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                }
            } else {
                HStack(spacing: FridgeFitTheme.Spacing.medium) {
                    ProgressView().tint(FridgeFitTheme.ColorToken.primary)
                    Text("Checking your pantry match…")
                        .font(FridgeFitTheme.Typography.cardTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                }
            }
        }
        .padding(FridgeFitTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            FridgeFitTheme.ColorToken.successBackground,
            in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.largeCard, style: .continuous)
        )
    }

}

private struct RecipeFridgeFixPanel: View {
    let recipe: Recipe
    let feasibility: RecipeFeasibilityResult
    let evaluations: [RecipeIngredientEvaluation]
    @ObservedObject var viewModel: SubstitutionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            HStack(spacing: FridgeFitTheme.Spacing.small) {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                    .frame(width: 32, height: 32)
                    .background(FridgeFitTheme.ColorToken.successBackground, in: Circle())
                    .accessibilityHidden(true)
                Text("FridgeFix Ingredient Substitutions")
                    .font(FridgeFitTheme.Typography.sectionTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Spacer()
                Text("AI ASSISTANT")
                    .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                    .padding(.horizontal, FridgeFitTheme.Spacing.small)
                    .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
                    .background(FridgeFitTheme.ColorToken.successBackground, in: Capsule())
            }

            Text("Ask FridgeFix for pantry-aware alternatives to ingredients you still need.")
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)

            ForEach(evaluations) { evaluation in
                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
                    Label(evaluation.ingredient.name, systemImage: "lightbulb")
                        .font(FridgeFitTheme.Typography.cardTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    SubstitutionSectionView(
                        recipeIngredient: evaluation.recipeIngredient,
                        recipe: recipe,
                        feasibility: feasibility,
                        viewModel: viewModel
                    )
                }
                .padding(FridgeFitTheme.Spacing.medium)
                .background(
                    FridgeFitTheme.ColorToken.canvas,
                    in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                )
            }

            Label(
                "Always check substitutions against your dietary and allergy needs.",
                systemImage: "info.circle"
            )
            .font(FridgeFitTheme.Typography.caption)
            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        }
        .padding(FridgeFitTheme.Spacing.large)
        .fridgeFitCardSurface()
    }
}

private struct RecipeIngredientsBreakdown: View {
    let recipe: Recipe
    let feasibility: RecipeFeasibilityResult?

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ingredients Breakdown")
                    .font(FridgeFitTheme.Typography.screenTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Spacer()
                Text("\(recipe.ingredients.count) items")
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }

            if let feasibility {
                let sections = RecipeDetailSections(feasibility: feasibility)
                if !sections.inStock.isEmpty {
                    RecipeIngredientGroup(
                        title: "Already in stock",
                        countLabel: "\(sections.inStock.count) ready",
                        tone: .success,
                        evaluations: sections.inStock
                    )
                }
                if !sections.stillNeeded.isEmpty {
                    RecipeIngredientGroup(
                        title: "Missing or insufficient",
                        countLabel: "\(sections.stillNeeded.count) needed",
                        tone: .danger,
                        evaluations: sections.stillNeeded
                    )
                }
                if !sections.optional.isEmpty {
                    RecipeIngredientGroup(
                        title: "Optional",
                        countLabel: "\(sections.optional.count) optional",
                        tone: .neutral,
                        evaluations: sections.optional
                    )
                }
            } else {
                ProgressView("Checking ingredient availability…")
                    .tint(FridgeFitTheme.ColorToken.primary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
    }
}

private struct RecipeIngredientGroup: View {
    let title: LocalizedStringKey
    let countLabel: LocalizedStringKey
    let tone: FridgeFitStatusTone
    let evaluations: [RecipeIngredientEvaluation]

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            HStack {
                Circle()
                    .fill(groupColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(title)
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Spacer()
                FridgeFitStatusBadge(title: countLabel, tone: tone)
            }
            ForEach(evaluations) { evaluation in
                RecipeDetailIngredientCard(evaluation: evaluation)
            }
        }
    }

    private var groupColor: Color {
        switch tone {
        case .success: FridgeFitTheme.ColorToken.primary
        case .warning: FridgeFitTheme.ColorToken.warningText
        case .neutral: FridgeFitTheme.ColorToken.textSecondary
        case .danger: FridgeFitTheme.ColorToken.accent
        }
    }
}

private struct RecipeDetailIngredientCard: View {
    let evaluation: RecipeIngredientEvaluation

    var body: some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.medium) {
            Image(systemName: evaluation.availability.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(evaluation.availability.tint)
                .frame(width: 32, height: 32)
                .background(statusBackground, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Text("\(evaluation.recipeIngredient.formattedQuantity) \(evaluation.ingredient.name)")
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text(detailText)
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
            Spacer(minLength: FridgeFitTheme.Spacing.small)
            Text(evaluation.availability.displayName)
                .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(evaluation.availability.tint)
                .padding(.horizontal, FridgeFitTheme.Spacing.small)
                .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
                .background(statusBackground, in: Capsule())
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
        .accessibilityElement(children: .combine)
    }

    private var detailText: String {
        switch evaluation.availability {
        case .available:
            "Have \(evaluation.formattedPantryQuantity ?? evaluation.recipeIngredient.formattedQuantity)"
        case .insufficient:
            evaluation.missingQuantity.map { "Need \(evaluation.recipeIngredient.unit.formatted($0)) more" }
                ?? "Not enough in stock"
        case .missing:
            evaluation.role == .optional ? "Optional and not in stock" : "Not in stock"
        case .quantityUnverified:
            "Check amount on hand: \(evaluation.formattedPantryQuantity ?? "unknown")"
        }
    }

    private var statusBackground: Color {
        switch evaluation.availability {
        case .available: FridgeFitTheme.ColorToken.successBackground
        case .insufficient: FridgeFitTheme.ColorToken.warningBackground
        case .missing: FridgeFitTheme.ColorToken.accent.opacity(0.14)
        case .quantityUnverified: FridgeFitTheme.ColorToken.disabledSurface
        }
    }
}

private struct RecipeInstructionsSection: View {
    let instructions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            Text("Cooking Instructions")
                .font(FridgeFitTheme.Typography.screenTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            if instructions.isEmpty {
                Text("No step-by-step instructions are available for this recipe.")
                    .font(FridgeFitTheme.Typography.body)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .padding(FridgeFitTheme.Spacing.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fridgeFitCardSurface()
            } else {
                ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.medium) {
                        Text(index + 1, format: .number)
                            .font(FridgeFitTheme.Typography.cardTitle)
                            .foregroundStyle(FridgeFitTheme.ColorToken.card)
                            .frame(width: 32, height: 32)
                            .background(FridgeFitTheme.ColorToken.primary, in: Circle())
                        Text(instruction)
                            .font(FridgeFitTheme.Typography.body)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(FridgeFitTheme.Spacing.medium)
                    .fridgeFitCardSurface()
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Step \(index + 1). \(instruction)")
                }
            }
        }
    }
}

private struct RecipeDetailSections {
    let inStock: [RecipeIngredientEvaluation]
    let stillNeeded: [RecipeIngredientEvaluation]
    let optional: [RecipeIngredientEvaluation]

    init(feasibility: RecipeFeasibilityResult) {
        inStock = feasibility.evaluatedIngredients.filter {
            $0.role == .essential && $0.availability == .available
        }
        stillNeeded = feasibility.evaluatedIngredients.filter {
            $0.role == .essential && $0.availability != .available
        }
        optional = feasibility.evaluatedIngredients.filter { $0.role == .optional }
    }

    static func unresolvedIngredients(in feasibility: RecipeFeasibilityResult) -> [RecipeIngredientEvaluation] {
        feasibility.evaluatedIngredients.filter {
            $0.role == .essential && $0.availability != .available
        }
    }
}

private func badgeTone(for status: RecipeFeasibilityStatus) -> FridgeFitStatusTone {
    switch status {
    case .makeable: .success
    case .almostMakeable: .warning
    case .notMakeable: .danger
    }
}
