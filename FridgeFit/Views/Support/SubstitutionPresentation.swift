//
//  SubstitutionPresentation.swift
//  FridgeFit
//

import SwiftUI

extension SubstitutionValidationStatus {
    var tint: Color {
        switch self {
        case .availableInPantry: return .green
        case .notInPantry: return .secondary
        case .insufficientQuantity: return .orange
        case .unsupportedUnit: return .blue
        case .rejected: return .red
        }
    }
}

/// "Find Substitute" affordance and results for one recipe ingredient.
/// Reads only from `SubstitutionViewModel`'s already-validated state - no
/// matching or pantry logic here.
///
/// Suggestions are generated on-device by Apple Intelligence, which isn't
/// available on every device, so there is a fourth state alongside idle,
/// loading and results: an explained unavailable state in place of a button
/// that could only fail. Nothing is fabricated when the model can't run.
struct SubstitutionSectionView: View {
    let recipeIngredient: RecipeIngredient
    let recipe: Recipe
    let feasibility: RecipeFeasibilityResult
    @ObservedObject var viewModel: SubstitutionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isLoading(for: recipeIngredient) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Finding substitutes\u{2026}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { viewModel.cancel(for: recipeIngredient) }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            } else if let suggestions = viewModel.suggestions(for: recipeIngredient), !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Suggestions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(suggestions) { suggestion in
                        SubstitutionSuggestionCard(suggestion: suggestion)
                    }
                    Text("Suggested on-device by Apple Intelligence. Pantry availability is checked against your pantry, not guessed.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if !viewModel.canFindSubstitutes {
                unavailableContent
            } else {
                Button {
                    Task { await viewModel.findSubstitutes(for: recipeIngredient, recipe: recipe, feasibility: feasibility) }
                } label: {
                    Label("Find Substitute", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let errorMessage = viewModel.errorMessage(for: recipeIngredient) {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.leading, 44)
        .padding(.vertical, 2)
    }

    /// Mirrors how `PantryRecipeIdeasView` and `ReceiptScannerView` explain
    /// an unavailable model, scaled down to an inline row rather than a
    /// full-screen `ContentUnavailableView`.
    @ViewBuilder
    private var unavailableContent: some View {
        let availability = viewModel.availability
        VStack(alignment: .leading, spacing: 2) {
            Label(availability.unavailableTitle ?? "Substitutes Unavailable", systemImage: "sparkles.slash")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(SubstitutionServiceError.substitutionUnavailable(availability).localizedDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// One substitution candidate, already validated against the pantry.
struct SubstitutionSuggestionCard: View {
    let suggestion: SubstitutionSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(suggestion.ingredientName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Label(suggestion.validationStatus.displayName, systemImage: suggestion.validationStatus.symbolName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(suggestion.validationStatus.tint)
            }

            if let statusDetail {
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(suggestion.explanation)
                .font(.caption)

            if let limitations = suggestion.limitations, !limitations.isEmpty {
                Text(limitations)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var statusDetail: String? {
        switch suggestion.validationStatus {
        case .availableInPantry:
            guard let have = suggestion.formattedPantryQuantity else { return "You have this in your pantry." }
            return "You have \(have)."
        case .insufficientQuantity:
            guard let have = suggestion.formattedPantryQuantity else { return nil }
            if let need = suggestion.formattedSuggestedQuantity {
                return "You have \(have), need \(need)."
            }
            return "You only have \(have)."
        case .unsupportedUnit:
            guard let have = suggestion.formattedPantryQuantity else { return nil }
            return "You have \(have) - check the amount yourself before using it."
        case .notInPantry:
            return "Not in your pantry."
        case .rejected:
            return nil
        }
    }
}
