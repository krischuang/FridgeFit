//
//  IngredientTile.swift
//  FridgeFit
//

import SwiftUI

/// A kitchen item as a card.
///
/// Two layouts: `compact` for the horizontal "Use First" strip, and the
/// fuller card for storage zones. Both state urgency in words as well as
/// colour.
struct IngredientTile: View {
    let item: PantryItem
    var compact = false
    var accent: Color = KitchenTheme.warmAccent

    private var expiryState: ExpiryState? { item.expiryState }

    var body: some View {
        if compact {
            compactCard
        } else {
            inventoryCard
        }
    }

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(item.storage.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            statusPill
        }
        .frame(width: 116, alignment: .topLeading)
        .frame(minHeight: 72, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(KitchenTheme.tile)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(KitchenTheme.separator, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var inventoryCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                categoryMarker

                Spacer(minLength: 8)

                if let stateText {
                    urgencyChip(text: stateText, tint: stateTint)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.ingredient.category.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.inventoryQuantity.displayText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let secondaryStatusText {
                    Text(secondaryStatusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(trailingTint)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: 132, alignment: .topLeading)
        .frame(minHeight: 128, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(KitchenTheme.tile.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var categoryMarker: some View {
        Circle()
            .fill(accent.opacity(0.78))
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(accent.opacity(0.30), lineWidth: 5)
            )
            .padding(.top, 4)
            .accessibilityHidden(true)
    }

    private var statusPill: some View {
        Text(trailingText)
            .font(.caption2.weight(.bold))
            .foregroundStyle(trailingTint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(trailingTint.opacity(0.12)))
            .lineLimit(1)
    }

    private func urgencyChip(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.12)))
    }

    private var cardStroke: Color {
        if let expiryState, expiryState.shouldPrioritise {
            return expiryState.urgency.tint.opacity(0.42)
        }
        return item.isLowStock ? KitchenTheme.low.opacity(0.38) : KitchenTheme.separator
    }

    /// "No expiry" is shown rather than left blank: an item nobody dated is
    /// a fact worth stating, and the blank it replaces reads as missing data.
    private var trailingText: String {
        if let expiryState {
            return expiryState.title
        }
        return "No expiry"
    }

    private var secondaryStatusText: String? {
        if expiryState?.shouldPrioritise == true || item.isLowStock {
            return nil
        }
        return trailingText
    }

    private var trailingTint: Color {
        if let expiryState, expiryState.shouldPrioritise {
            return expiryState.urgency.tint
        }
        return item.isLowStock ? KitchenTheme.low : .secondary
    }

    private var stateText: String? {
        if let expiryState, expiryState.shouldPrioritise {
            return expiryState.title
        }
        return item.isLowStock ? "Low" : nil
    }

    private var stateTint: Color {
        if let expiryState, expiryState.shouldPrioritise {
            return expiryState.urgency.tint
        }
        return KitchenTheme.low
    }

    private var accessibilityText: String {
        var parts = [item.name, item.inventoryQuantity.displayText]
        if let expiryState {
            parts.append("Expires \(expiryState.title.lowercased())")
        }
        if item.isLowStock {
            parts.append("Low stock")
        }
        return parts.joined(separator: ", ")
    }
}
