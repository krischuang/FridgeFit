//
//  ProfileView.swift
//  FridgeFit
//

import FirebaseAuth
import SwiftUI

/// The signed-in user's account, recipe preferences, kitchen impact and
/// connected-device entry point.
///
/// ## Where Kitchen Impact's numbers come from
///
/// The same `InventoryStore` that Home and My Fridge use, handed down from
/// `ContentView` - so the same `InventoryEventRepository` that
/// `AppDependencies` selected, reading the same records. This screen
/// performs no storage decision of its own.
///
/// It used to: `loadProfileData()` built a `FirestoreInventoryEventRepository()`
/// inline. That was correct while Firestore was the only backend and became
/// wrong the moment `PersistenceConfiguration` could choose - with SwiftData
/// selected, Kitchen Impact counted cloud events while My Fridge counted
/// local ones, and neither screen had any way to notice it disagreed with
/// the other.
///
/// Sharing the store rather than re-fetching also means the counts follow
/// the user: finishing an item in My Fridge reloads that one store, and
/// Profile re-renders from it with no refresh of its own.
///
/// ## What this does not do
///
/// It does not copy anything. Kitchen Impact previously counted events in
/// Firestore; it now counts events in whichever store `AppDependencies`
/// opened, which under the shipped configuration is the local one. Any
/// outcomes a user logged before this change are still in Firestore,
/// untouched and still readable by launching with `-persistence firebase` -
/// they are simply not counted in SwiftData mode, because that mode has
/// never claimed to contain them. This is the project's existing rule, not
/// a new exception: see `PersistenceConfiguration` and
/// `FIREBASE_COMPATIBILITY_AND_ROLLBACK.md` §4, which specify one source of
/// truth per mode and no automatic import. Closing that gap is a deliberate
/// product decision (§4.1 sketches the safe one-way shape) and is out of
/// scope here.
struct ProfileView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.fundsEnvironment) private var funds
    /// The kitchen's items and activity log. Constructor-injected, not
    /// defaulted, for the reason `InventoryStore` and `RecipeViewModel`
    /// already record: the only possible default is an in-memory store, and
    /// a screen that silently reports sample data as the user's own is a
    /// worse failure than a compile error.
    @ObservedObject private var inventory: InventoryStore
    @State private var onlineRecipePreferences = OnlineRecipePreferences.default
    @State private var selectedSection: ProfileSection = .preferences
    @State private var isShowingNotificationNotice = false
    private let onFindRecipes: () -> Void
    private let onOpenPantry: () -> Void

    init(
        inventory: InventoryStore,
        onFindRecipes: @escaping () -> Void,
        onOpenPantry: @escaping () -> Void = {}
    ) {
        self.inventory = inventory
        self.onFindRecipes = onFindRecipes
        self.onOpenPantry = onOpenPantry
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
                appHeader
                header
                ProfileSectionTabs(selection: $selectedSection)

                switch selectedSection {
                case .preferences:
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
                case .impact:
                    // The approved Impact & Budget layout starts at its own
                    // hero card, so the account card is not repeated above
                    // it. Preferences and Settings keep it unchanged.
                    ProfileImpactView(
                        inventory: inventory,
                        funds: funds,
                        onFindRecipes: onFindRecipes,
                        onOpenPantry: onOpenPantry
                    )
                case .settings:
                    accountCard
                    ProfileSettingsView()
                }
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.top, FridgeFitTheme.Spacing.small)
            .padding(.bottom, FridgeFitTheme.Spacing.xLarge)
        }
        .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FridgeFitTheme.ColorToken.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await loadProfileData() }
    }

    /// The screen title and its one-line summary, above the section tabs.
    ///
    /// The title is the same on every tab, as in the approved design: the
    /// screen *is* Profile & Settings, and the segmented control below says
    /// which part of it is open. Only the summary line changes, so the user
    /// still gets a description of what they are looking at.
    private var header: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
            Text("Profile & Settings")
                .font(FridgeFitTheme.Typography.pageTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(selectedSection.subtitle)
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

            // The design puts a bell here. FridgeFit ships no notification
            // feature yet, so rather than a control that silently does
            // nothing, this says so when tapped.
            Button {
                isShowingNotificationNotice = true
            } label: {
                Image(systemName: "bell")
                    .font(.body)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Notifications")
            .accessibilityHint("Explains why reminders are unavailable")

            compactAvatar
        }
        .frame(minHeight: 44)
        .alert("Reminders aren't set up yet", isPresented: $isShowingNotificationNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("FridgeFit doesn't send expiry reminders yet, so there is nothing to show here.")
        }
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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
                    value: impactValue(kitchenImpact.finishedCount),
                    title: "Finished",
                    detail: impactDetail,
                    systemImage: "checkmark.circle"
                )
                impactMetric(
                    value: impactValue(kitchenImpact.discardedCount),
                    title: "Discarded",
                    detail: impactDetail,
                    systemImage: "trash"
                )
            }
        }
    }

    /// Reads straight off the shared store, so this section is never a
    /// separate snapshot of the activity log.
    private var kitchenImpact: KitchenImpactSummary { inventory.kitchenImpact }

    private func impactValue(_ count: Int?) -> String {
        count.map(String.init) ?? "—"
    }

    /// One line per state. The previous wording said "No activity yet" both
    /// when the log was empty and when it had failed to load, which told a
    /// user with a broken read that they had never cooked.
    private var impactDetail: String {
        switch kitchenImpact.state {
        case .loading: return "Loading activity…"
        case .empty: return "No activity yet"
        case .counted: return "items logged"
        case .unavailable: return "Activity unavailable"
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

    /// Reads preferences, then asks the shared store to refresh itself.
    ///
    /// `inventory.load()` rather than a fetch of our own, so Profile cannot
    /// end up holding a different view of the log from My Fridge. It is the
    /// same call My Fridge makes in its own `.task`, and it is safe to
    /// repeat: the store reloads and publishes, and every screen observing
    /// it re-renders. Opening Profile first is therefore enough to populate
    /// Kitchen Impact, and both its loading and its failure state come from
    /// that one load.
    private func loadProfileData() async {
        onlineRecipePreferences = UserDefaultsOnlineRecipePreferencesStore().load()
        await inventory.load()
    }
}

private enum ProfileSection: String, CaseIterable, Identifiable {
    case preferences
    case impact
    case settings

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .preferences: "Preferences"
        case .impact: "Impact & Budget"
        case .settings: "Settings"
        }
    }

    /// The line under the screen title. Taken from the approved design,
    /// one per tab.
    var subtitle: LocalizedStringKey {
        switch self {
        case .preferences: "Your culinary identity & account"
        case .impact: "Track grocery savings, waste reduction & pantry stats"
        case .settings: "Preferences, notifications & system sync"
        }
    }
}

private struct ProfileSectionTabs: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selection: ProfileSection

    var body: some View {
        VStack(spacing: FridgeFitTheme.Spacing.xSmall) {
            if dynamicTypeSize.isAccessibilitySize {
                ForEach(ProfileSection.allCases) { section in
                    ProfileSectionButton(section: section, selection: $selection)
                }
            } else {
                HStack(spacing: FridgeFitTheme.Spacing.xSmall) {
                    ForEach(ProfileSection.allCases) { section in
                        ProfileSectionButton(section: section, selection: $selection)
                    }
                }
            }
        }
        .padding(FridgeFitTheme.Spacing.xSmall)
        .frame(maxWidth: .infinity)
        .background(
            FridgeFitTheme.ColorToken.disabledSurface,
            in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Profile sections")
    }
}

private struct ProfileSectionButton: View {
    let section: ProfileSection
    @Binding var selection: ProfileSection

    var body: some View {
        Button {
            selection = section
        } label: {
            Text(section.title)
                .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                .foregroundStyle(selection == section ? FridgeFitTheme.ColorToken.card : FridgeFitTheme.ColorToken.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    selection == section ? FridgeFitTheme.ColorToken.primary : .clear,
                    in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == section ? .isSelected : [])
    }
}

private extension OnlineRecipePreferences {
    var isConfigured: Bool {
        diet != .none || !intolerances.isEmpty || maxReadyTimeMinutes != nil
    }
}

#Preview {
    NavigationStack {
        ProfileView(
            inventory: InventoryStore(
                pantryRepository: InMemoryPantryRepository(),
                eventRepository: InMemoryInventoryEventRepository()
            ),
            onFindRecipes: {}
        )
        .environmentObject(AuthViewModel())
    }
}
