//
//  RecipePresentation.swift
//  FridgeFit
//

import SwiftUI

extension IngredientAvailability {
    var tint: Color {
        switch self {
        case .available: return .green
        case .insufficient: return .orange
        case .missing: return .red
        case .quantityUnverified: return .blue
        }
    }
}

extension RecipeFeasibilityStatus {
    var tint: Color {
        switch self {
        case .makeable: return .green
        case .almostMakeable: return .orange
        case .notMakeable: return .red
        }
    }
}

/// One recipe's row in the recipe list: title plus a quick feasibility
/// readout. Reads only from the already-computed `RecipeFeasibilityResult`
/// - no matching logic here.
struct RecipeRow: View {
    let recipe: Recipe
    let feasibility: RecipeFeasibilityResult?

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemImage: recipe.symbolName ?? "fork.knife", tint: feasibility?.status.tint ?? .gray)
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.body)
                if let feasibility {
                    HStack(spacing: 6) {
                        Image(systemName: feasibility.status.symbolName)
                            .foregroundStyle(feasibility.status.tint)
                        Text(feasibility.status.title)
                        Text("\u{00B7} \(feasibility.matchedCount)/\(feasibility.totalRequiredCount) (\(Int(feasibility.coveragePercentage))%)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                } else {
                    Text("Checking pantry\u{2026}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
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
                            .foregroundStyle(.secondary)
                    }
                }
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
