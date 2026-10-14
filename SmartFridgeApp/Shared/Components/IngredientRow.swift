import SwiftUI

struct IngredientRow: View {
    let ingredient: Ingredient
    var showsStorage = false

    private var expiryState: ExpiryState? {
        ExpiryService.state(for: ingredient.expiryDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ingredient.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    if let detailText {
                        Text(detailText)
                            .font(.subheadline)
                            .foregroundStyle(detailTint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                }

                Spacer(minLength: 12)

                Text(trailingText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(trailingTint)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())

            Divider()
                .overlay(SmartFridgeTheme.separator)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var trailingText: String {
        if let expiryState, expiryState.shouldPrioritise {
            expiryState.title
        } else {
            ingredient.quantity.displayText
        }
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

    private var detailText: String? {
        var pieces: [String] = []

        if ingredient.openedState == .opened {
            pieces.append("Opened")
        }

        if ingredient.isLowStock {
            pieces.append("Low")
        }

        if showsStorage {
            pieces.append(ingredient.storageLocation.title)
        }

        if let expiryState, !expiryState.shouldPrioritise, expiryState.urgency == .thisWeek {
            pieces.append("Expires this week")
        }

        return pieces.isEmpty ? nil : pieces.joined(separator: " · ")
    }

    private var detailTint: Color {
        ingredient.isLowStock ? SmartFridgeTheme.low : .secondary
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
