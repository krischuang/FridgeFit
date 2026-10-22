//
//  AuthFormComponents.swift
//  FridgeFit
//

import SwiftUI

/// The pieces the sign-in and sign-up screens share, so the two stay one
/// design rather than two that drifted.
///
/// Everything here is built from `FridgeFitTheme` tokens. The Fresh Botanical
/// palette the redesign specifies is the palette the design system already
/// carries - canvas `#F7F5EC`, card `#FFFFFF`, Herb Green `#356B52` - so none
/// of it is restated as a literal here.

/// Placeholder text for an auth field.
///
/// Passed as a field's `prompt` rather than its title string: the default
/// placeholder picks up the field's tint, which turned the email example into
/// something that read as a tappable link.
enum AuthFieldPrompt {
    static func text(_ value: String) -> Text {
        Text(value).foregroundStyle(FridgeFitTheme.ColorToken.textSecondary.opacity(0.75))
    }
}

/// Logo mark, wordmark, title and subtitle, stacked and centred.
struct AuthBrandHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: FridgeFitTheme.Spacing.small) {
            logoMark
                .padding(.bottom, FridgeFitTheme.Spacing.xSmall)

            Text("FRIDGEFIT")
                .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                .tracking(2)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)

            Text(title)
                .font(FridgeFitTheme.Typography.pageTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            Text(subtitle)
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var logoMark: some View {
        Image(systemName: "refrigerator.fill")
            .accessibilityHidden(true)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(FridgeFitTheme.ColorToken.primary)
            .frame(width: 72, height: 72)
            .background(
                FridgeFitTheme.ColorToken.card,
                in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.largeCard, style: .continuous)
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: "bolt.fill")
                    .accessibilityHidden(true)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    .frame(width: 24, height: 24)
                    .background(FridgeFitTheme.ColorToken.honey, in: Circle())
                    .offset(x: 8, y: -8)
            }
            .accessibilityHidden(true)
    }
}

/// A labelled white field with a leading glyph, and a focus ring in Herb
/// Green so the active field is obvious without a colour change inside it.
///
/// `trailingLabel` is the optional control that sits opposite the field's
/// label, which is where the design puts "Forgot Password?".
struct AuthField<Content: View, TrailingLabel: View>: View {
    let label: String
    let systemImage: String
    var isFocused: Bool
    @ViewBuilder var content: () -> Content
    @ViewBuilder var trailingLabel: () -> TrailingLabel

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
            HStack {
                Text(label)
                    .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Spacer(minLength: FridgeFitTheme.Spacing.small)
                trailingLabel()
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.xSmall)

            HStack(spacing: FridgeFitTheme.Spacing.medium) {
                Image(systemName: systemImage)
                    .font(.callout)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                content()
                    .font(FridgeFitTheme.Typography.body)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    // Herb Green caret and selection. Without it the fields
                    // inherit the system blue, which is the one thing on
                    // these screens that would not be the brand palette.
                    .tint(FridgeFitTheme.ColorToken.primary)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .frame(minHeight: 52)
            .background(
                FridgeFitTheme.ColorToken.card,
                in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                    .stroke(
                        isFocused ? FridgeFitTheme.ColorToken.primary : FridgeFitTheme.ColorToken.border,
                        lineWidth: isFocused ? 2 : 1
                    )
            }
            .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

extension AuthField where TrailingLabel == EmptyView {
    init(
        label: String,
        systemImage: String,
        isFocused: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            label: label,
            systemImage: systemImage,
            isFocused: isFocused,
            content: content,
            trailingLabel: { EmptyView() }
        )
    }
}

/// Password entry with the show/hide toggle the design asks for.
///
/// The toggle is why neither screen asks for the password twice: the user can
/// read back what they typed, which is what a confirmation field was standing
/// in for.
struct AuthPasswordEntry: View {
    @Binding var password: String
    var isRevealed: Bool
    var placeholder: String
    var textContentType: UITextContentType
    var onToggleReveal: () -> Void
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: FridgeFitTheme.Spacing.small) {
            Group {
                if isRevealed {
                    TextField("", text: $password, prompt: AuthFieldPrompt.text(placeholder))
                } else {
                    SecureField("", text: $password, prompt: AuthFieldPrompt.text(placeholder))
                }
            }
            .textContentType(textContentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .onSubmit(onSubmit)

            Button(action: onToggleReveal) {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.callout)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
        }
    }
}

/// A rule the hairline divider runs behind, with its caption sitting on the
/// canvas colour in the middle.
struct AuthDivider: View {
    let title: String

    var body: some View {
        HStack(spacing: FridgeFitTheme.Spacing.medium) {
            line
            Text(title)
                .font(FridgeFitTheme.Typography.metadata)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .fixedSize()
            line
        }
        .accessibilityHidden(true)
    }

    private var line: some View {
        Rectangle()
            .fill(FridgeFitTheme.ColorToken.border)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

/// Auth errors in the palette's error state rather than a bare red line.
struct AuthMessageBanner: View {
    enum Tone {
        case error
        case confirmation
    }

    let message: String
    let tone: Tone

    var body: some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: tone == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.footnote)
            Text(message)
                .font(FridgeFitTheme.Typography.metadata)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tone.foreground)
        .padding(FridgeFitTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.background, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

extension AuthMessageBanner.Tone {
    var foreground: Color {
        switch self {
        case .error: return FridgeFitTheme.ColorToken.errorText
        case .confirmation: return FridgeFitTheme.ColorToken.primary
        }
    }

    var background: Color {
        switch self {
        case .error: return FridgeFitTheme.ColorToken.errorBackground
        case .confirmation: return FridgeFitTheme.ColorToken.successBackground
        }
    }
}
