//
//  KitchenTheme.swift
//  FridgeFit
//

import SwiftUI
import UIKit
/// Colours for the Kitchen tab.
///
/// Shared surfaces and brand colours delegate to `FridgeFitTheme`; only the
/// pantry-specific urgency colours remain here.
enum KitchenTheme {
    static let background = FridgeFitTheme.ColorToken.canvas
    static let surface = FridgeFitTheme.ColorToken.card
    static let tile = FridgeFitTheme.ColorToken.card
    static let separator = FridgeFitTheme.ColorToken.border
    static let forest = FridgeFitTheme.ColorToken.primary
    static let warmAccent = FridgeFitTheme.ColorToken.primary

    static let urgent = adaptive(light: 0xB43C31, dark: 0xFF9C8C)
    static let soon = adaptive(light: 0x926114, dark: 0xFFD58A)
    static let low = adaptive(light: 0x765A00, dark: 0xF3C767)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
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
            return FridgeFitTheme.ColorToken.textSecondary
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
