//
//  FridgeFitDesignSystem.swift
//  FridgeFit
//
//  Shared presentation foundation for FridgeFit. Feature screens intentionally
//  opt in to these tokens and styles in their own implementation passes.
//

import SwiftUI
import UIKit

/// Semantic visual tokens shared across FridgeFit.
///
/// The light appearance matches the warm, botanical FridgeFit palette. Each
/// colour also supplies a considered dark appearance so controls remain
/// legible without defining a separate dark-mode design system.
enum FridgeFitTheme {
    enum ColorToken {
        static let canvas = adaptive(light: 0xF7F5EC, dark: 0x202821)
        static let secondaryBackground = adaptive(light: 0xEEF1E9, dark: 0x253027)
        static let card = adaptive(light: 0xFFFFFF, dark: 0x2A342E)
        static let primary = adaptive(light: 0x356B52, dark: 0x8FC59B)
        /// Filled brand surfaces need a darker green than `primary` in Dark
        /// Mode so white button and hero text keeps sufficient contrast.
        static let brandFill = adaptive(light: 0x356B52, dark: 0x3C7056)
        static let primaryMuted = adaptive(light: 0xA9C6A1, dark: 0x466B51)
        static let textPrimary = adaptive(light: 0x26352C, dark: 0xF1F4EF)
        static let textSecondary = adaptive(light: 0x637064, dark: 0xB9C3B9)
        static let border = adaptive(light: 0xDFE5DC, dark: 0x3B453E)
        static let controlBorder = adaptive(light: 0x829086, dark: 0x708075)
        static let successBackground = adaptive(light: 0xE5EEE0, dark: 0x294332)
        static let successText = adaptive(light: 0x356B52, dark: 0x8FC59B)
        static let warningBackground = adaptive(light: 0xFFF0D4, dark: 0x4B3A1D)
        static let warningText = adaptive(light: 0x926114, dark: 0xFFD58A)
        static let danger = adaptive(light: 0xC84F42, dark: 0xFF9C8C)
        static let errorBackground = adaptive(light: 0xFCEBE7, dark: 0x453B34)
        static let errorText = adaptive(light: 0xB43C31, dark: 0xFF9C8C)
        static let accent = adaptive(light: 0xED8066, dark: 0xFF9D88)
        static let disabledSurface = adaptive(light: 0xE8ECE6, dark: 0x343C36)
        static let disabledText = adaptive(light: 0x5C685D, dark: 0xB9C3B9)
        /// Honey Yellow, the palette's second accent. Used for figures that
        /// need to read against the filled green surfaces, where neither
        /// `primary` nor `accent` has enough contrast.
        static let honey = adaptive(light: 0xF3C767, dark: 0xF7D489)

        private static func adaptive(light: UInt32, dark: UInt32) -> Color {
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: dark)
                    : UIColor(hex: light)
            })
        }
    }

    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 20
        static let section: CGFloat = 24
        static let screen: CGFloat = 32
    }

    enum Radius {
        static let small: CGFloat = 8
        static let control: CGFloat = 12
        static let card: CGFloat = 16
        static let largeCard: CGFloat = 20
        static let pill: CGFloat = 999
    }

    enum Typography {
        static let hero: Font = .largeTitle.weight(.bold)
        /// The name of the screen, above any in-screen navigation. Larger
        /// than `screenTitle`, which titles a region *within* a screen.
        static let pageTitle: Font = .title.weight(.bold)
        static let screenTitle: Font = .title2.weight(.bold)
        static let sectionTitle: Font = .headline
        /// For sections that are the user's main landmarks on a long
        /// scrolling screen, where `sectionTitle` does not separate them
        /// enough from the card text underneath.
        static let sectionTitleProminent: Font = .title3.weight(.bold)
        static let cardTitle: Font = .body.weight(.semibold)
        static let body: Font = .body
        static let supporting: Font = .subheadline
        static let metadata: Font = .footnote
        static let button: Font = .body.weight(.semibold)
        static let caption: Font = .caption
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Filled action treatment for primary, task-completing buttons.
struct FridgeFitPrimaryButtonStyle: ButtonStyle {
    /// Fully rounds the button. The sign-in and sign-up screens call for a
    /// pill CTA; every other caller keeps the control radius, so the default
    /// leaves them untouched.
    var isPill = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FridgeFitTheme.Typography.button)
            .foregroundStyle(isEnabled ? .white : FridgeFitTheme.ColorToken.disabledText)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .background(
                isEnabled ? FridgeFitTheme.ColorToken.brandFill : FridgeFitTheme.ColorToken.disabledSurface,
                in: RoundedRectangle(
                    cornerRadius: isPill ? FridgeFitTheme.Radius.pill : FridgeFitTheme.Radius.control,
                    style: .continuous
                )
            )
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Outlined treatment for secondary actions.
struct FridgeFitSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FridgeFitTheme.Typography.button)
            .foregroundStyle(isEnabled ? FridgeFitTheme.ColorToken.primary : FridgeFitTheme.ColorToken.disabledText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .background(
                isEnabled ? FridgeFitTheme.ColorToken.card : FridgeFitTheme.ColorToken.disabledSurface,
                in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                    .stroke(FridgeFitTheme.ColorToken.controlBorder, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .accessibilityAddTraits(.isButton)
    }
}

enum FridgeFitChipTone {
    case standard
    case success
    case warning
}

/// Compact, pill-shaped button treatment for filters and selections.
struct FridgeFitChipStyle: ButtonStyle {
    let isSelected: Bool
    var tone: FridgeFitChipTone = .standard

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
            .foregroundStyle(foreground)
            .frame(minHeight: 44)
            .padding(.horizontal, FridgeFitTheme.Spacing.medium)
            .background(background, in: Capsule())
            .overlay {
                Capsule().stroke(border, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        guard !isSelected else { return FridgeFitTheme.ColorToken.brandFill }
        switch tone {
        case .standard: return FridgeFitTheme.ColorToken.card
        case .success: return FridgeFitTheme.ColorToken.successBackground
        case .warning: return FridgeFitTheme.ColorToken.warningBackground
        }
    }

    private var foreground: Color {
        guard !isSelected else { return .white }
        switch tone {
        case .standard, .success: return FridgeFitTheme.ColorToken.primary
        case .warning: return FridgeFitTheme.ColorToken.warningText
        }
    }

    private var border: Color {
        FridgeFitTheme.ColorToken.controlBorder
    }
}

/// A white, bordered content surface for reusable card layouts.
struct FridgeFitCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(FridgeFitTheme.ColorToken.card, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous)
                    .stroke(FridgeFitTheme.ColorToken.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.035), radius: 3, y: 1)
    }
}

extension View {
    func fridgeFitCardSurface() -> some View {
        modifier(FridgeFitCardSurface())
    }
}

enum FridgeFitStatusTone {
    case success
    case warning
    case neutral
    case danger
}

/// Non-interactive status label. Pair the label text with its meaning; colour
/// is supportive rather than the only status indicator.
struct FridgeFitStatusBadge: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var tone: FridgeFitStatusTone = .neutral

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .font(FridgeFitTheme.Typography.caption.weight(.semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, FridgeFitTheme.Spacing.small)
        .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
        .background(background, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var background: Color {
        switch tone {
        case .success: return FridgeFitTheme.ColorToken.successBackground
        case .warning: return FridgeFitTheme.ColorToken.warningBackground
        case .neutral: return FridgeFitTheme.ColorToken.disabledSurface
        case .danger: return FridgeFitTheme.ColorToken.errorBackground
        }
    }

    private var foreground: Color {
        switch tone {
        case .success: return FridgeFitTheme.ColorToken.successText
        case .warning: return FridgeFitTheme.ColorToken.warningText
        case .neutral: return FridgeFitTheme.ColorToken.disabledText
        case .danger: return FridgeFitTheme.ColorToken.errorText
        }
    }
}

/// Circular, SF Symbol-compatible treatment for compact icon actions.
struct FridgeFitIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? FridgeFitTheme.ColorToken.primary : FridgeFitTheme.ColorToken.textSecondary)
            .frame(width: 44, height: 44)
            .background(FridgeFitTheme.ColorToken.card, in: Circle())
            .overlay {
                Circle().stroke(FridgeFitTheme.ColorToken.controlBorder, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.7 : (isEnabled ? 1 : 0.65))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .accessibilityAddTraits(.isButton)
    }
}

/// Botanical text fields with an explicit, accessible control boundary.
struct FridgeFitTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            .padding(.horizontal, FridgeFitTheme.Spacing.medium)
            .frame(minHeight: 44)
            .background(
                FridgeFitTheme.ColorToken.card,
                in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                    .stroke(FridgeFitTheme.ColorToken.controlBorder, lineWidth: 1)
            }
    }
}
