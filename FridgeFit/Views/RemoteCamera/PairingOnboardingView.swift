//
//  PairingOnboardingView.swift
//  FridgeFit
//

import SwiftUI

/// Presentation-only guide for the existing account-scoped camera discovery
/// and WebRTC connection flow. It introduces no pairing mechanism of its own.
struct PairingOnboardingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xLarge) {
                hero

                Text("Set up in three steps")
                    .font(FridgeFitTheme.Typography.sectionTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

                stepCard(
                    number: 1,
                    title: "Sign in on both phones",
                    detail: "Open FridgeFit on both phones and sign in with the same account.",
                    systemImage: "person.2.fill"
                )

                stepCard(
                    number: 2,
                    title: "Start the kitchen camera",
                    detail: "On the phone used as the kitchen camera, select \"Use as Camera\" and open Camera Mode. Keep Camera Mode active so the device remains discoverable.",
                    systemImage: "video.fill"
                )

                stepCard(
                    number: 3,
                    title: "Connect from your remote phone",
                    detail: "On the second phone, choose \"Use as Remote Camera\". Select the available camera to begin the existing connection flow.",
                    systemImage: "viewfinder"
                )

                Label("You can return here from Connected Devices whenever you need a refresher.", systemImage: "info.circle")
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .padding(FridgeFitTheme.Spacing.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.vertical, FridgeFitTheme.Spacing.large)
        }
        .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
        .navigationTitle("How Live AI Works")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            phoneIllustration

            Text("A kitchen camera, with you in control")
                .font(FridgeFitTheme.Typography.screenTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            Text("Live AI Camera uses your two signed-in FridgeFit phones: one stays in the kitchen, while the other lets you watch and control it.")
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(FridgeFitTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [FridgeFitTheme.ColorToken.successBackground, FridgeFitTheme.ColorToken.card],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.largeCard, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.largeCard, style: .continuous)
                .stroke(FridgeFitTheme.ColorToken.border, lineWidth: 1)
        }
    }

    private var phoneIllustration: some View {
        HStack(spacing: FridgeFitTheme.Spacing.small) {
            guidePhone(symbol: "video.fill", label: "Kitchen camera")
            Image(systemName: "arrow.left.and.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 36, height: 36)
                .background(FridgeFitTheme.ColorToken.card, in: Circle())
            guidePhone(symbol: "viewfinder", label: "Remote phone")
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kitchen camera phone connected to a remote phone")
    }

    private func guidePhone(symbol: String, label: String) -> some View {
        VStack(spacing: FridgeFitTheme.Spacing.xSmall) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 58, height: 64)
                .background(FridgeFitTheme.ColorToken.card, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
            Text(label)
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        }
    }

    private func stepCard(number: Int, title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.medium) {
            Text("\(number)")
                .font(FridgeFitTheme.Typography.cardTitle.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(FridgeFitTheme.ColorToken.brandFill, in: Circle())

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Label(title, systemImage: systemImage)
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text(detail)
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fridgeFitCardSurface()
    }
}

#if DEBUG
#Preview("Live AI Setup Guide") {
    NavigationStack {
        PairingOnboardingView()
    }
}
#endif
