import SwiftUI

struct IngredientTile: View {
    let ingredient: Ingredient
    var compact = false
    var accent: Color = SmartFridgeTheme.warmAccent

    private var expiryState: ExpiryState? {
        ExpiryService.state(for: ingredient.expiryDate)
    }

    var body: some View {
        if compact {
            compactCard
        } else {
            inventoryRow
        }
    }

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ingredient.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(ingredient.storageLocation.title)
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
                .fill(SmartFridgeTheme.tile)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(SmartFridgeTheme.separator, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var inventoryRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                categoryMarker

                Spacer(minLength: 8)

                if let stateText {
                    urgencyDot(text: stateText, tint: stateTint)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(ingredient.category.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text(ingredient.quantity.displayText)
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
                .fill(SmartFridgeTheme.tile.opacity(0.96))
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

    private func urgencyDot(text: String, tint: Color) -> some View {
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
            expiryState.urgency.tint.opacity(0.42)
        } else if ingredient.isLowStock {
            SmartFridgeTheme.low.opacity(0.38)
        } else {
            SmartFridgeTheme.separator
        }
    }

    private var trailingText: String {
        if let expiryState, expiryState.shouldPrioritise {
            expiryState.title
        } else if ingredient.expiryDate == nil {
            "No expiry"
        } else {
            ExpiryService.state(for: ingredient.expiryDate)?.title ?? "No expiry"
        }
    }

    private var secondaryStatusText: String? {
        if expiryState?.shouldPrioritise == true || ingredient.isLowStock {
            return nil
        }
        return trailingText
    }

    private var trailingTint: Color {
        if let expiryState, expiryState.shouldPrioritise {
            expiryState.urgency.tint
        } else if ingredient.isLowStock {
            SmartFridgeTheme.low
        } else {
            .secondary
        }
    }

    private var stateText: String? {
        if let expiryState, expiryState.shouldPrioritise {
            expiryState.urgency == .expired ? "Expired" : expiryState.title
        } else if ingredient.isLowStock {
            "Low"
        } else {
            nil
        }
    }

    private var stateTint: Color {
        if let expiryState, expiryState.shouldPrioritise {
            expiryState.urgency.tint
        } else {
            SmartFridgeTheme.low
        }
    }

    private var accessibilityText: String {
        var parts = [ingredient.name, ingredient.quantity.displayText]
        if let expiryState {
            parts.append("Expires \(expiryState.title.lowercased())")
        }
        if ingredient.isLowStock {
            parts.append("Low stock")
        }
        return parts.joined(separator: ", ")
    }
}
