//
//  ProfileView.swift
//  FridgeFit
//

import FirebaseAuth
import SwiftUI

/// The signed-in user's account and connected-device entry point.
///
/// This screen intentionally presents only account data FridgeFit currently
/// has. Profile preferences, kitchen-impact totals, and saved recipe counts
/// will be added when their corresponding product state exists.
struct ProfileView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var onlineRecipePreferences = OnlineRecipePreferences.default
    @State private var kitchenImpact = KitchenImpact()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
                appHeader
                header
                sectionTabs
                accountCard
                personalisationCard
                kitchenImpactCard
                dietarySafeguardsCard
                savedRecipesCard
                applicationSettingsCard

                if let errorMessage = authViewModel.errorMessage {
                    errorCard(message: errorMessage)
                }

                signOutButton
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.top, FridgeFitTheme.Spacing.small)
            .padding(.bottom, FridgeFitTheme.Spacing.xLarge)
        }
        .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadProfileData() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
            Text("Profile & Settings")
                .font(.title3.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            Text("Your account and connected kitchen devices")
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var appHeader: some View {
        HStack(spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: "refrigerator")
                .font(.body.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 32, height: 32)
                .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))

            Text("FridgeFit")
                .font(FridgeFitTheme.Typography.cardTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)

            Spacer()

            compactAvatar
        }
        .frame(minHeight: 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("FridgeFit, signed in as \(accountName)")
    }

    /// Mirrors the three visual categories in the Stitch reference. These
    /// labels are intentionally informational until profile preferences and
    /// settings have their own editable destinations.
    private var sectionTabs: some View {
        HStack(spacing: FridgeFitTheme.Spacing.xSmall) {
            profileTab("Preferences", selected: true)
            profileTab("Impact & Waste", selected: false)
            profileTab("Settings", selected: false)
        }
        .padding(FridgeFitTheme.Spacing.xSmall)
        .frame(maxWidth: .infinity)
        .background(FridgeFitTheme.ColorToken.card, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                .stroke(FridgeFitTheme.ColorToken.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Profile sections: Preferences, Impact and Waste, Settings")
    }

    private func profileTab(_ title: LocalizedStringKey, selected: Bool) -> some View {
        Text(title)
            .font(FridgeFitTheme.Typography.caption.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? FridgeFitTheme.ColorToken.textPrimary : FridgeFitTheme.ColorToken.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(selected ? FridgeFitTheme.ColorToken.canvas : .clear, in: Capsule())
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            HStack(spacing: FridgeFitTheme.Spacing.medium) {
                avatar

                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                    Text(accountName)
                        .font(FridgeFitTheme.Typography.cardTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                        .lineLimit(2)

                    Text(accountEmail)
                        .font(FridgeFitTheme.Typography.supporting)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    FridgeFitStatusBadge(
                        title: "Signed in",
                        systemImage: "checkmark.circle.fill",
                        tone: .success
                    )
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Divider().overlay(FridgeFitTheme.ColorToken.border)
                HStack {
                    Text("Profile setup")
                        .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    Spacer()
                    FridgeFitStatusBadge(
                        title: onlineRecipePreferences.isConfigured ? "Preferences configured" : "Setup incomplete",
                        tone: onlineRecipePreferences.isConfigured ? .success : .warning
                    )
                }
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Account: \(accountName), \(accountEmail), signed in")
    }

    private var avatar: some View {
        profileAvatar(size: 48, initialsFont: .title3.weight(.semibold))
            .accessibilityHidden(true)
    }

    private var compactAvatar: some View {
        profileAvatar(size: 32, initialsFont: .caption.weight(.semibold))
            .overlay {
                Circle().stroke(FridgeFitTheme.ColorToken.primaryMuted.opacity(0.45), lineWidth: 2)
            }
            .accessibilityHidden(true)
    }

    private func profileAvatar(size: CGFloat, initialsFont: Font) -> some View {
        Group {
            if let photoURL = authViewModel.user?.photoURL {
                AsyncImage(url: photoURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        initialsAvatar(font: initialsFont)
                    }
                }
            } else {
                initialsAvatar(font: initialsFont)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func initialsAvatar(font: Font) -> some View {
        Text(initials)
            .font(font)
            .foregroundStyle(FridgeFitTheme.ColorToken.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FridgeFitTheme.ColorToken.primaryMuted.opacity(0.45))
    }

    private var personalisationCard: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
                Image(systemName: "slider.horizontal.3")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                    .frame(width: 28, height: 28)
                    .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))

                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                    Text("Personalise your meals")
                        .font(FridgeFitTheme.Typography.cardTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    Text(personalisationDescription)
                        .font(FridgeFitTheme.Typography.metadata)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if onlineRecipePreferences.isConfigured {
                preferenceChips
            } else {
                FridgeFitStatusBadge(title: "Not configured", systemImage: "slider.horizontal.3", tone: .neutral)
            }

            NavigationLink {
                OnlineRecipePreferencesView(initial: onlineRecipePreferences) { updated in
                    UserDefaultsOnlineRecipePreferencesStore().save(updated)
                    onlineRecipePreferences = updated
                }
            } label: {
                Label(
                    onlineRecipePreferences.isConfigured ? "Edit preferences" : "Set preferences",
                    systemImage: "arrow.right"
                )
                .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens recipe preference settings")
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private var kitchenImpactCard: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            HStack {
                Text("Kitchen Impact")
                    .font(FridgeFitTheme.Typography.sectionTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Spacer()
                Text("Recent activity")
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }

            HStack(spacing: FridgeFitTheme.Spacing.small) {
                impactMetric(
                    value: kitchenImpact.isAvailable ? "\(kitchenImpact.finishedCount)" : "—",
                    title: "Finished",
                    detail: kitchenImpact.isAvailable ? "items logged" : "No activity yet",
                    systemImage: "checkmark.circle"
                )
                impactMetric(
                    value: kitchenImpact.isAvailable ? "\(kitchenImpact.discardedCount)" : "—",
                    title: "Discarded",
                    detail: kitchenImpact.isAvailable ? "items logged" : "No activity yet",
                    systemImage: "trash"
                )
            }
        }
    }

    private func impactMetric(value: String, title: String, detail: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 28, height: 28)
                .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))
            Text(value)
                .font(FridgeFitTheme.Typography.screenTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            Text(title)
                .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            Text(detail)
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FridgeFitTheme.Spacing.medium)
        .frame(minHeight: 104, alignment: .topLeading)
        .fridgeFitCardSurface()
    }

    private var dietarySafeguardsCard: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            HStack {
                Label("Dietary Safeguards", systemImage: "heart.text.square")
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Spacer()
                FridgeFitStatusBadge(
                    title: onlineRecipePreferences.intolerances.isEmpty ? "None configured" : "Configured",
                    tone: onlineRecipePreferences.intolerances.isEmpty ? .warning : .success
                )
            }

            Text(dietaryDescription)
                .font(FridgeFitTheme.Typography.metadata)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !onlineRecipePreferences.intolerances.isEmpty {
                FlowLayout(spacing: FridgeFitTheme.Spacing.small) {
                    ForEach(onlineRecipePreferences.intolerances.sorted(by: { $0.displayName < $1.displayName })) { intolerance in
                        FridgeFitStatusBadge(title: LocalizedStringKey(intolerance.displayName), systemImage: "checkmark", tone: .success)
                    }
                }
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private var savedRecipesCard: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            HStack {
                Label("Saved Recipes", systemImage: "bookmark")
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Spacer()
                Text("Unavailable")
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }

            VStack(spacing: FridgeFitTheme.Spacing.small) {
                Image(systemName: "bookmark")
                    .font(.title3)
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                    .frame(width: 40, height: 40)
                    .background(FridgeFitTheme.ColorToken.successBackground, in: Circle())
                    .accessibilityHidden(true)
                Text("Saved recipes are unavailable")
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text("Recipes you save will appear here when this feature is available.")
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private var applicationSettingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Application settings")
                .padding(.bottom, FridgeFitTheme.Spacing.small)

            settingsRow(
                title: "Expiry Reminders",
                detail: "Not configured",
                systemImage: "bell.badge",
                showsChevron: false
            )

            Divider().overlay(FridgeFitTheme.ColorToken.border)

            settingsRow(
                title: "Storage & Sync",
                detail: "Uses your signed-in FridgeFit account",
                systemImage: "arrow.triangle.2.circlepath",
                showsChevron: false
            )

            Divider().overlay(FridgeFitTheme.ColorToken.border)

            NavigationLink {
                ConnectedDevicesView(identity: DeviceIdentity.current())
            } label: {
                settingsRow(
                    title: "Connected Devices",
                    detail: "Set up your fridge camera",
                    systemImage: "iphone.gen3.radiowaves.left.and.right",
                    showsChevron: true
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens device setup and Remote Camera")

            Divider().overlay(FridgeFitTheme.ColorToken.border)

            settingsRow(
                title: "About FridgeFit",
                detail: appVersion,
                systemImage: "questionmark.circle",
                showsChevron: false
            )
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private func settingsRow(title: String, detail: String, systemImage: String, showsChevron: Bool) -> some View {
        HStack(spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 28, height: 28)
                .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text(detail)
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
        }
        .frame(minHeight: 48)
    }

    private func errorCard(message: String) -> some View {
        Label {
            Text(message)
                .font(FridgeFitTheme.Typography.supporting)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(FridgeFitTheme.ColorToken.danger)
        .padding(FridgeFitTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FridgeFitTheme.ColorToken.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var signOutButton: some View {
        Button {
            authViewModel.signOut()
        } label: {
            Text("Sign out of account")
                .font(FridgeFitTheme.Typography.metadata)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(authViewModel.isLoading)
        .accessibilityHint("Signs out of FridgeFit on this device")
        .overlay {
            if authViewModel.isLoading {
                ProgressView()
                    .tint(FridgeFitTheme.ColorToken.primary)
            }
        }
    }

    private func sectionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            .textCase(.uppercase)
    }

    private var accountName: String {
        guard let user = authViewModel.user else { return "FridgeFit member" }
        if let displayName = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !displayName.isEmpty {
            return displayName
        }
        if let email = user.email, let localPart = email.split(separator: "@").first, !localPart.isEmpty {
            return String(localPart)
        }
        return "FridgeFit member"
    }

    private var accountEmail: String {
        authViewModel.user?.email ?? "Signed-in account"
    }

    private var initials: String {
        let components = accountName.split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "_" || $0 == "-" })
        let letters = components.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "F" : String(letters).uppercased()
    }

    private var personalisationDescription: String {
        onlineRecipePreferences.isConfigured
            ? onlineRecipePreferences.summary
            : "Recipe preferences are not configured yet."
    }

    private var dietaryDescription: String {
        onlineRecipePreferences.intolerances.isEmpty
            ? "No dietary safeguards are configured for recipe discovery."
            : "These ingredient-based safeguards are applied to recipe discovery."
    }

    private var preferenceChips: some View {
        FlowLayout(spacing: FridgeFitTheme.Spacing.small) {
            if onlineRecipePreferences.diet != .none {
                FridgeFitStatusBadge(title: LocalizedStringKey(onlineRecipePreferences.diet.displayName), tone: .success)
            }
            if let maxReadyTimeMinutes = onlineRecipePreferences.maxReadyTimeMinutes {
                FridgeFitStatusBadge(title: "Up to \(maxReadyTimeMinutes) min", systemImage: "clock", tone: .neutral)
            }
            ForEach(onlineRecipePreferences.intolerances.sorted(by: { $0.displayName < $1.displayName })) { intolerance in
                FridgeFitStatusBadge(title: LocalizedStringKey(intolerance.displayName), tone: .success)
            }
        }
    }

    private var appVersion: String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown version"
        guard let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String, !build.isEmpty else {
            return "Version \(version)"
        }
        return "Version \(version) (\(build))"
    }

    private func loadProfileData() async {
        onlineRecipePreferences = UserDefaultsOnlineRecipePreferencesStore().load()
        kitchenImpact.isLoading = true
        defer { kitchenImpact.isLoading = false }

        do {
            let events = try await FirestoreInventoryEventRepository().fetchAll(limit: InventoryStore.activityFetchLimit)
            kitchenImpact.finishedCount = events.filter { $0.kind == .finished }.count
            kitchenImpact.discardedCount = events.filter { $0.kind == .discarded }.count
            kitchenImpact.isAvailable = true
        } catch {
            kitchenImpact.isAvailable = false
        }
    }
}

private struct KitchenImpact {
    var finishedCount = 0
    var discardedCount = 0
    var isLoading = false
    var isAvailable = false
}

private extension OnlineRecipePreferences {
    var isConfigured: Bool {
        diet != .none || !intolerances.isEmpty || maxReadyTimeMinutes != nil
    }
}

#Preview {
    NavigationStack {
        ProfileView()
            .environmentObject(AuthViewModel())
    }
}
