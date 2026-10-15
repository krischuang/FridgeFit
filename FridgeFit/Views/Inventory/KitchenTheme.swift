//
//  KitchenTheme.swift
//  FridgeFit
//

import SwiftUI
import UIKit

/// Colours for the Kitchen tab.
///
/// Built on the system grouped-background palette rather than fixed hex
/// values, so the kitchen inherits Dark Mode and Increase Contrast for free
/// and sits beside the Pantry and Recipes tabs instead of looking like a
/// different app. The three status colours are explicit because "expired"
/// has to read as urgent in both appearances, which a semantic colour
/// doesn't guarantee.
enum KitchenTheme {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let tile = Color(uiColor: .secondarySystemGroupedBackground)
    static let separator = Color.primary.opacity(0.10)
    static let urgent = Color(red: 0.70, green: 0.18, blue: 0.12)
    static let soon = Color(red: 0.72, green: 0.42, blue: 0.12)
    static let low = Color(red: 0.64, green: 0.41, blue: 0.08)

    /// Darker in light mode, lighter in dark mode - a single colour can't do
    /// both and stay legible on the tile background.
    static let forest = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.68, green: 0.86, blue: 0.60, alpha: 1)
            : UIColor(red: 0.10, green: 0.27, blue: 0.13, alpha: 1)
    })

    static let warmAccent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.56, green: 0.78, blue: 0.50, alpha: 1)
            : UIColor(red: 0.22, green: 0.45, blue: 0.22, alpha: 1)
    })
}

extension ExpiryUrgency {
    /// How this urgency is coloured. Paired with text in every place it is
    /// used - colour alone would be the only signal for anyone who can't
    /// distinguish these two reds.
    var tint: Color {
        switch self {
        case .expired, .today:
            return KitchenTheme.urgent
        case .tomorrow, .soon:
            return KitchenTheme.soon
        case .thisWeek, .none:
            return .secondary
        }
    }
}

extension View {
    func kitchenInlineNavigationTitle() -> some View {
        navigationBarTitleDisplayMode(.inline)
    }

    func kitchenIngredientTextInput() -> some View {
        textInputAutocapitalization(.words)
    }

    func kitchenDecimalKeyboard() -> some View {
        keyboardType(.decimalPad)
    }
}
