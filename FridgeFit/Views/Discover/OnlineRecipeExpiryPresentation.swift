//
//  OnlineRecipeExpiryPresentation.swift
//  FridgeFit
//

import SwiftUI

/// Display wording for near-expiry pantry items on Discover.
enum OnlineRecipeExpiryPresentation {
    /// "today", "tomorrow", "in 2 days".
    static func whenText(for use: UrgentIngredientUse) -> String {
        switch use.urgency {
        case .today: return "today"
        case .tomorrow: return "tomorrow"
        default:
            if let days = use.daysUntilExpiry, days > 1 { return "in \(days) days" }
            return "soon"
        }
    }

    /// "Milk (tomorrow), Spinach (in 2 days)".
    static func list(_ uses: [UrgentIngredientUse]) -> String {
        uses.map { "\($0.ingredientName) (\(whenText(for: $0)))" }.joined(separator: ", ")
    }

    static func tint(for urgency: ExpiryUrgency?) -> Color {
        switch urgency {
        case .today: return KitchenTheme.urgent
        case .tomorrow: return KitchenTheme.soon
        default: return FridgeFitTheme.ColorToken.warningText
        }
    }
}

/// Compact badge for a Discover result row.
struct OnlineRecipeExpiryBadge: View {
    let use: OnlineRecipeExpiryUse

    var body: some View {
        if use.usesExpiredIngredient {
            Label("Uses expired \(use.expired.joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.errorText)
        } else if use.usesUrgentIngredient {
            Label("Uses up \(OnlineRecipeExpiryPresentation.list(use.urgent))", systemImage: "clock.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(OnlineRecipeExpiryPresentation.tint(for: use.mostUrgent))
                .lineLimit(2)
        }
    }
}
