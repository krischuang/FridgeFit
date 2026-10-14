import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum SmartFridgeTheme {
    static let background = Color.platformKitchenBackground
    static let surface = Color.platformKitchenSurface
    static let tile = Color.platformKitchenTile
    static let separator = Color.primary.opacity(0.10)
    static let forest = Color.platformKitchenForest
    static let warmAccent = Color.platformKitchenAccent
    static let urgent = Color(red: 0.70, green: 0.18, blue: 0.12)
    static let soon = Color(red: 0.72, green: 0.42, blue: 0.12)
    static let low = Color(red: 0.64, green: 0.41, blue: 0.08)

    static var kitchenGradient: LinearGradient {
        LinearGradient(
            colors: [
                background,
                Color.platformKitchenWash
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private extension Color {
    static var platformKitchenBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var platformKitchenWash: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    static var platformKitchenSurface: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    static var platformKitchenTile: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .textBackgroundColor)
        #endif
    }

    static var platformKitchenForest: Color {
        #if os(iOS)
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.68, green: 0.86, blue: 0.60, alpha: 1)
                : UIColor(red: 0.10, green: 0.27, blue: 0.13, alpha: 1)
        })
        #else
        Color.primary
        #endif
    }

    static var platformKitchenAccent: Color {
        #if os(iOS)
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.56, green: 0.78, blue: 0.50, alpha: 1)
                : UIColor(red: 0.22, green: 0.45, blue: 0.22, alpha: 1)
        })
        #else
        Color.accentColor
        #endif
    }
}

extension View {
    @ViewBuilder
    func smartInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func smartInsetGroupedListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }

    @ViewBuilder
    func smartIngredientTextInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.words)
        #else
        self
        #endif
    }

    @ViewBuilder
    func smartDecimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }
}

extension ExpiryUrgency {
    var tint: Color {
        switch self {
        case .expired, .today:
            SmartFridgeTheme.urgent
        case .tomorrow, .soon:
            SmartFridgeTheme.soon
        case .thisWeek, .none:
            .secondary
        }
    }
}
