//
//  RecipePresentation.swift
//  FridgeFit
//

import SwiftUI
import UIKit

extension IngredientAvailability {
    var tint: Color {
        switch self {
        case .available: return FridgeFitTheme.ColorToken.primary
        case .insufficient: return FridgeFitTheme.ColorToken.warningText
        case .missing: return FridgeFitTheme.ColorToken.danger
        case .quantityUnverified: return FridgeFitTheme.ColorToken.textSecondary
        }
    }
}

extension RecipeFeasibilityStatus {
    var tint: Color {
        switch self {
        case .makeable: return FridgeFitTheme.ColorToken.primary
        case .almostMakeable: return FridgeFitTheme.ColorToken.warningText
        case .notMakeable: return FridgeFitTheme.ColorToken.danger
        }
    }
}

/// One recipe's row in the recipe list: title plus a quick feasibility
/// readout. Reads only from the already-computed `RecipeFeasibilityResult`
/// - no matching logic here.
struct RecipeRow: View {
    let recipe: Recipe
    let feasibility: RecipeFeasibilityResult?
    var isSaved = false
    /// Decoded stored photo for a saved recipe (see `RecipeViewModel.thumbnail(for:)`).
    var image: UIImage? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                    .fill(artworkBackground)
                    .frame(minHeight: 132)
                if RecipePhoto<EmptyView>.hasPhoto(image: image, imageURL: recipe.imageURL) {
                    Color.clear
                        .frame(height: 132)
                        .frame(maxWidth: .infinity)
                        .overlay {
                            RecipePhoto(image: image, imageURL: recipe.imageURL) { symbolArtwork }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
                        .accessibilityHidden(true)
                } else {
                    symbolArtwork
                }
                VStack {
                    HStack(alignment: .top) {
                        if isSaved {
                            FridgeFitStatusBadge(title: "Saved", systemImage: "bookmark.fill", tone: .neutral)
                        }
                        Spacer()
                        if let feasibility {
                            FridgeFitStatusBadge(
                                title: "\(Int(feasibility.coveragePercentage))% match",
                                systemImage: feasibility.status.symbolName,
                                tone: badgeTone(for: feasibility.status)
                            )
                        }
                    }
                    Spacer()
                }
                .padding(FridgeFitTheme.Spacing.medium)
            }

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
                Text(recipe.title)
                    .font(FridgeFitTheme.Typography.screenTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text(recipe.summary)
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .lineLimit(3)
            }

            FlowLayout(spacing: FridgeFitTheme.Spacing.small) {
                if let minutes = recipe.totalCookingTimeInMinutes {
                    FridgeFitStatusBadge(title: "\(minutes) min", systemImage: "timer", tone: .neutral)
                }
                if let difficulty = recipe.difficulty {
                    FridgeFitStatusBadge(title: LocalizedStringKey(difficulty.displayName), systemImage: "dial.low", tone: .neutral)
                }
                if let servings = recipe.servings {
                    FridgeFitStatusBadge(title: "\(servings) servings", systemImage: "person.2", tone: .neutral)
                }
            }

            if let feasibility {
                Label(statusText(for: feasibility), systemImage: feasibility.status.symbolName)
                    .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                    .foregroundStyle(feasibility.status.tint)
                if !unavailableIngredientNames(in: feasibility).isEmpty {
                    Label(
                        "Still need \(unavailableIngredientNames(in: feasibility).formatted())",
                        systemImage: "basket"
                    )
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .lineLimit(2)
                }
            } else {
                Label("Checking pantry…", systemImage: "hourglass")
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var symbolArtwork: some View {
        Image(systemName: recipe.symbolName ?? "fork.knife")
            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            .foregroundStyle(FridgeFitTheme.ColorToken.primary)
            .accessibilityHidden(true)
    }

    private var artworkBackground: Color {
        switch feasibility?.status {
        case .makeable: return FridgeFitTheme.ColorToken.successBackground
        case .almostMakeable: return FridgeFitTheme.ColorToken.warningBackground
        case .notMakeable: return FridgeFitTheme.ColorToken.errorBackground
        case nil: return FridgeFitTheme.ColorToken.disabledSurface
        }
    }

    private func badgeTone(for status: RecipeFeasibilityStatus) -> FridgeFitStatusTone {
        switch status {
        case .makeable: return .success
        case .almostMakeable: return .warning
        case .notMakeable: return .danger
        }
    }

    private func statusText(for feasibility: RecipeFeasibilityResult) -> String {
        let coverage = "\(feasibility.matchedCount) of \(feasibility.totalRequiredCount) ingredients ready"
        switch feasibility.status {
        case .makeable: return "Ready to cook · \(coverage)"
        case .almostMakeable: return "Almost ready · \(coverage)"
        case .notMakeable: return "Shopping needed · \(coverage)"
        }
    }

    private func unavailableIngredientNames(in feasibility: RecipeFeasibilityResult) -> [String] {
        (feasibility.missingIngredients + feasibility.insufficientIngredients)
            .map(\.ingredient.name)
    }
}

/// One recipe ingredient's row in the detail screen: name, role, and
/// availability against the pantry. Reads only from the already-computed
/// `RecipeIngredientEvaluation` - no matching or conversion logic here.
struct RecipeIngredientRow: View {
    let evaluation: RecipeIngredientEvaluation

    private var isUnresolvedOptional: Bool {
        evaluation.role == .optional && evaluation.availability != .available
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isUnresolvedOptional ? "circle" : evaluation.availability.symbolName)
                .foregroundStyle(isUnresolvedOptional ? .secondary : evaluation.availability.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(evaluation.ingredient.name)
                    if evaluation.role == .optional {
                        Text("optional")
                            .font(.caption2)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    }
                }
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var detailText: String {
        switch evaluation.availability {
        case .available:
            let onHand = evaluation.formattedPantryQuantity ?? evaluation.recipeIngredient.formattedQuantity
            return "\(onHand) / \(evaluation.recipeIngredient.formattedQuantity) required"
        case .insufficient:
            if let missing = evaluation.missingQuantity {
                return "Need \(evaluation.recipeIngredient.unit.formatted(missing)) more"
            }
            return "Insufficient quantity"
        case .missing:
            return evaluation.role == .optional
                ? "Optional, missing"
                : "Need \(evaluation.recipeIngredient.formattedQuantity)"
        case .quantityUnverified:
            return "Check amount (have \(evaluation.formattedPantryQuantity ?? "unknown"))"
        }
    }
}
