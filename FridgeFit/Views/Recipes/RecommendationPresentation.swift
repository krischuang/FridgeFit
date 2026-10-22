//
//  RecommendationPresentation.swift
//  FridgeFit
//

import SwiftUI

extension RecipeReadiness {
    var tint: Color {
        switch self {
        case .readyToCook: return FridgeFitTheme.ColorToken.successText
        // Blue, matching `IngredientAvailability.quantityUnverified` - this
        // readiness exists precisely because an amount couldn't be
        // verified, so it should read the same colour as the ingredient
        // row that caused it rather than as a warning.
        case .almostReady: return FridgeFitTheme.ColorToken.primary
        case .needsOneToTwoIngredients: return FridgeFitTheme.ColorToken.warningText
        }
    }
}

extension ExpiryUrgency {
    /// Colour for an expiry chip on a recommendation.
    ///
    /// Shares the Kitchen tab's meaning: the nearer the date, the hotter
    /// the colour.
    var recommendationTint: Color {
        switch self {
        case .expired: return KitchenTheme.urgent
        case .today: return KitchenTheme.urgent
        case .tomorrow, .soon: return KitchenTheme.soon
        case .thisWeek, .none: return FridgeFitTheme.ColorToken.textSecondary
        }
    }
}

/// One reason a recipe was recommended, as a compact chip.
struct RecommendationReasonChip: View {
    let reason: RecommendationReason

    var body: some View {
        Label(reason.displayText, systemImage: reason.symbolName)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.tint.opacity(0.12), in: Capsule())
            .foregroundStyle(.tint)
    }
}

/// One recommendation's row: the dish, how ready it is, and why it was
/// chosen.
///
/// Every line here is read from an already-computed `RecipeSuitability`.
/// There is no matching, conversion, or ranking logic in the view - the
/// same discipline `RecipeRow` follows with `RecipeFeasibilityResult`.
struct RecommendationRow: View {
    let recommendation: RecipeRecommendation
    let feedback: SessionRecipeFeedbackAction?

    private var suitability: RecipeSuitability { recommendation.suitability }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                IconBadge(
                    systemImage: recommendation.recipe.symbolName ?? "fork.knife",
                    tint: recommendation.readiness.tint
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(recommendation.recipe.title)
                        .font(.body)
                    HStack(spacing: 6) {
                        Image(systemName: recommendation.readiness.symbolName)
                            .foregroundStyle(recommendation.readiness.tint)
                        Text(recommendation.readiness.displayName)
                        Text("\u{00B7} \(suitability.pantryMatchPercentage)% of essentials")
                            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    }
                    .font(.caption)
                }
                Spacer()
                if let feedback {
                    FeedbackBadge(action: feedback)
                }
            }

            if let line = metadataLine {
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }

            if !recommendation.rankingReasons.isEmpty {
                // Wraps rather than scrolls: a horizontal scroll view
                // inside a List row swallows the row's own tap target.
                FlowLayout(spacing: 6) {
                    ForEach(recommendation.rankingReasons, id: \.self) { reason in
                        RecommendationReasonChip(reason: reason)
                    }
                }
            }

            if !suitability.urgentIngredients.isEmpty {
                urgentLine
            }

            if suitability.usesExpiredIngredient {
                expiredLine
            }

            if !suitability.unverifiedIngredients.isEmpty {
                // Stated explicitly so the row can never imply a verified
                // amount it doesn't have.
                Label(
                    "Check your amount of \(suitability.unverifiedIngredients.formattedList)",
                    systemImage: "questionmark.circle"
                )
                .font(.caption2)
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
            }

            if !suitability.shoppingIngredients.isEmpty {
                Label(
                    "Still need \(suitability.shoppingIngredients.formattedList)",
                    systemImage: "cart"
                )
                .font(.caption2)
                .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Only the metadata the recipe actually states.
    private var metadataLine: String? {
        var parts: [String] = []
        if let minutes = recommendation.recipe.totalCookingTimeInMinutes {
            parts.append("\(minutes) min")
        }
        if let difficulty = recommendation.recipe.difficulty {
            parts.append(difficulty.displayName)
        }
        if let cuisine = recommendation.recipe.cuisine {
            parts.append(cuisine.displayName)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private var urgentLine: some View {
        let described = suitability.urgentIngredients
            .map { use -> String in
                guard let days = use.daysUntilExpiry else { return use.ingredientName }
                switch days {
                case 0: return "\(use.ingredientName) (today)"
                case 1: return "\(use.ingredientName) (tomorrow)"
                default: return "\(use.ingredientName) (\(days) days)"
                }
            }
            .formattedList

        return Label("Uses \(described)", systemImage: "clock.badge.exclamationmark")
            .font(.caption2)
            .foregroundStyle(
                suitability.urgentIngredients.first?.urgency.recommendationTint ?? FridgeFitTheme.ColorToken.warningText
            )
    }

    /// Shown as a caution, never as a reason to cook. Expired food gives no
    /// ranking credit - see `EvaluateRecipeSuitabilityUseCase.expiryUse`.
    private var expiredLine: some View {
        Label(
            "\(suitability.expiredIngredients.formattedList) in your pantry is past its date - replace before cooking",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption2)
        .foregroundStyle(FridgeFitTheme.ColorToken.errorText)
    }
}

/// A small marker showing what the user did with a recipe this session.
struct FeedbackBadge: View {
    let action: SessionRecipeFeedbackAction

    var body: some View {
        Image(systemName: symbolName)
            .font(.caption)
            .foregroundStyle(tint)
            .accessibilityLabel(accessibilityLabel)
    }

    private var symbolName: String {
        switch action {
        case .saved: return "bookmark.fill"
        case .skipped: return "eye.slash.fill"
        case .reported: return "hand.thumbsdown.fill"
        }
    }

    private var tint: Color {
        switch action {
        case .saved: return FridgeFitTheme.ColorToken.primary
        case .skipped, .reported: return FridgeFitTheme.ColorToken.textSecondary
        }
    }

    private var accessibilityLabel: String {
        switch action {
        case .saved: return "Saved this session"
        case .skipped: return "Skipped this session"
        case .reported(let reason): return "Reported: \(reason.displayText)"
        }
    }
}

extension Array where Element == String {
    /// "a", "a and b", "a, b and c" - for ingredient lists in explanations.
    var formattedList: String {
        switch count {
        case 0: return ""
        case 1: return self[0]
        case 2: return "\(self[0]) and \(self[1])"
        default: return "\(dropLast().joined(separator: ", ")) and \(self[count - 1])"
        }
    }
}

/// A minimal wrapping stack for the reason chips.
///
/// Written here rather than pulled in as a dependency: SwiftUI has no
/// built-in wrapping layout, and the reason chips are the only thing in
/// the app that needs one.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(CGFloat.zero) { total, row in
            total + row.height + (total > 0 ? spacing : 0)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width

            if needed > maxWidth && !current.indices.isEmpty {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }

        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
