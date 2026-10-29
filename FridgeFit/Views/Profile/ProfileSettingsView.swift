import FirebaseAuth
import SwiftUI

struct ProfileSettingsView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.deleteAccountUseCaseFactory) private var deleteAccountUseCaseFactory
    /// Which store the pantry is actually in, so the sync row can state it
    /// instead of guessing. `nil` where it was not supplied (previews), in
    /// which case the row is left out rather than asserting a backend.
    @Environment(\.persistenceBackend) private var persistenceBackend

    let store: ProfileSettingsStoring
    @State private var settings = ProfileSettings()
    @State private var isPresentingDeleteAccount = false

    init(store: ProfileSettingsStoring = UserDefaultsProfileSettingsStore()) {
        self.store = store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.section) {
            // Six rows used to sit above this, in two sections ("Expiry &
            // Notifications", "Storage & Pantry Behaviour"), each rendered
            // greyed out with a padlock and the word "Unavailable". They were
            // not settings - none of them could be switched on, and together
            // they made the first screenful of Settings a list of things
            // FridgeFit cannot do. Advertising six absent features above the
            // two real ones reads as an unfinished app, so they are gone
            // rather than disabled. What remains is what works.
            SettingsSectionTitle(title: "Kitchen & Units", systemImage: "ruler")
            SettingsCard {
                MeasurementPreferenceRow(selection: $settings.measurementSystem)
                SettingsDivider()
                ServingPreferenceRow(servings: $settings.defaultServingSize)
            }

            // Replaces a single row that read "Sync status - Firestore
            // account sync - Private, user-scoped cloud storage". That was
            // untrue in the shipping configuration, where the pantry is a
            // local database and never leaves the device. The copy is now
            // derived from the backend that was actually built, so it cannot
            // drift from reality again - see `StorageDisclosure`.
            SettingsSectionTitle(title: "Where your data lives", systemImage: "externaldrive")
            SettingsCard {
                if let persistenceBackend {
                    let disclosures = StorageDisclosure.all(for: persistenceBackend)
                    ForEach(Array(disclosures.enumerated()), id: \.element.id) { index, disclosure in
                        if index > 0 { SettingsDivider() }
                        StorageDisclosureRow(disclosure: disclosure)
                    }
                } else {
                    SettingsStatusRow(
                        title: "Storage",
                        detail: "Not available on this screen outside the running app",
                        systemImage: "externaldrive",
                        status: "Unknown"
                    )
                }
            }

            Text(StorageDisclosure.noSyncNotice)
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, FridgeFitTheme.Spacing.xSmall)

            AppInformationCard(version: appVersion, build: appBuild)

            Button {
                authViewModel.signOut()
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(FridgeFitTheme.ColorToken.danger)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FridgeFitSecondaryButtonStyle())
            .disabled(authViewModel.isLoading)
            .accessibilityHint("Signs out of FridgeFit on this device")

            Text("Logged in as \(accountEmail)")
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .frame(maxWidth: .infinity)
                .textSelection(.enabled)

            // Last, visually separated, and behind a sheet plus a
            // confirmation dialog. Offered only when the composition root
            // supplied a way to actually do it - a Delete Account button
            // that cannot delete anything is the thing this section exists
            // to stop being.
            if let deleteAccountUseCaseFactory {
                deleteAccountSection(factory: deleteAccountUseCaseFactory)
            }
        }
        .task { settings = store.load() }
        .onChange(of: settings) { _, newValue in store.save(newValue) }
    }

    private func deleteAccountSection(factory: DeleteAccountUseCaseFactory) -> some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            SettingsSectionTitle(title: "Danger zone", systemImage: "exclamationmark.triangle")

            Button {
                isPresentingDeleteAccount = true
            } label: {
                Label("Delete Account", systemImage: "trash")
                    .foregroundStyle(FridgeFitTheme.ColorToken.danger)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(FridgeFitSecondaryButtonStyle())
            .accessibilityIdentifier("open-delete-account")
            .accessibilityHint("Permanently deletes your FridgeFit account and all of your data. You'll be asked to confirm.")

            Text("Permanently removes your account and everything in it. This can't be undone.")
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .padding(.top, FridgeFitTheme.Spacing.small)
        .sheet(isPresented: $isPresentingDeleteAccount) {
            DeleteAccountSheet(viewModel: DeleteAccountViewModel(useCase: factory.make()))
        }
    }

    private var accountEmail: String {
        authViewModel.user?.email ?? "signed-in FridgeFit account"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
}

private struct SettingsSectionTitle: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        HStack {
            Text(title)
                .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .textCase(.uppercase)
            Spacer()
            Image(systemName: systemImage)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, FridgeFitTheme.Spacing.xSmall)
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .fridgeFitCardSurface()
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(FridgeFitTheme.ColorToken.border)
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
    }
}

private enum SettingsRowTone {
    case neutral
    case warning
    case danger
}

private struct SettingsRowIcon: View {
    let systemImage: String
    let tone: SettingsRowTone

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.medium))
            .foregroundStyle(foreground)
            .frame(width: 36, height: 36)
            .background(background, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small))
            .accessibilityHidden(true)
    }

    private var foreground: Color {
        switch tone {
        case .neutral: FridgeFitTheme.ColorToken.primary
        case .warning: FridgeFitTheme.ColorToken.warningText
        case .danger: FridgeFitTheme.ColorToken.danger
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: FridgeFitTheme.ColorToken.successBackground
        case .warning: FridgeFitTheme.ColorToken.warningBackground
        case .danger: FridgeFitTheme.ColorToken.errorBackground
        }
    }
}

private struct MeasurementPreferenceRow: View {
    @Binding var selection: MeasurementSystemPreference

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.medium) {
                SettingsRowIcon(systemImage: "scalemass", tone: .neutral)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Measurement system").font(FridgeFitTheme.Typography.cardTitle)
                    Text("Display preference only; stored inventory units are unchanged")
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Picker("Measurement system", selection: $selection) {
                ForEach(MeasurementSystemPreference.allCases, id: \.self) { system in
                    Text(system.title).tag(system)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(FridgeFitTheme.Spacing.large)
    }
}

private struct ServingPreferenceRow: View {
    @Binding var servings: Int

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.medium) {
                SettingsRowIcon(systemImage: "person.2", tone: .neutral)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Default serving size").font(FridgeFitTheme.Typography.cardTitle)
                    Text("Saved display preference; automatic recipe scaling is not connected yet")
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Button { servings = max(1, servings - 1) } label: {
                    Image(systemName: "minus").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Decrease default serving size")
                .disabled(servings <= 1)
                Spacer()
                Text("\(servings) servings")
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .monospacedDigit()
                Spacer()
                Button { servings = min(12, servings + 1) } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Increase default serving size")
                .disabled(servings >= 12)
            }
            .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            .background(FridgeFitTheme.ColorToken.disabledSurface, in: Capsule())
        }
        .padding(FridgeFitTheme.Spacing.large)
    }
}

/// One "where your data lives" line.
///
/// The location is carried by text as well as by icon and colour, so the
/// distinction between on-device and cloud is not conveyed by colour alone.
private struct StorageDisclosureRow: View {
    let disclosure: StorageDisclosure

    var body: some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.medium) {
            SettingsRowIcon(systemImage: systemImage, tone: .neutral)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: disclosure.title)
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: disclosure.location.shortLabel)
                    .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)

                Text(verbatim: disclosure.detail)
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(FridgeFitTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text(verbatim: "\(disclosure.title). \(disclosure.location.shortLabel). \(disclosure.detail)")
        )
    }

    private var systemImage: String {
        switch disclosure.location {
        case .onDeviceOnly: "iphone"
        case .privateCloud: "lock.icloud"
        // Deliberately not a lock: this is the one row where the data goes
        // to someone other than FridgeFit, and the icon should not imply
        // the same protection as the rows that stay under the account.
        case .thirdParty: "arrow.up.forward.app"
        }
    }
}

private struct SettingsStatusRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let status: String

    var body: some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.medium) {
            SettingsRowIcon(systemImage: systemImage, tone: .neutral)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(FridgeFitTheme.Typography.cardTitle)
                Text(verbatim: detail)
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
            Spacer(minLength: FridgeFitTheme.Spacing.small)
            Label(status, systemImage: "checkmark.circle.fill")
                .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(FridgeFitTheme.Spacing.large)
        .accessibilityElement(children: .combine)
    }
}

private struct AppInformationCard: View {
    let version: String
    let build: String

    var body: some View {
        HStack(spacing: FridgeFitTheme.Spacing.medium) {
            Image(systemName: "leaf.fill")
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 36, height: 36)
                .background(FridgeFitTheme.ColorToken.successBackground, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("FridgeFit for iOS").font(FridgeFitTheme.Typography.cardTitle)
                Text("Version \(version)")
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
            Spacer()
            Text("Build \(build)")
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .padding(.horizontal, FridgeFitTheme.Spacing.small)
                .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
                .background(FridgeFitTheme.ColorToken.disabledSurface, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small))
        }
        .padding(FridgeFitTheme.Spacing.large)
        .fridgeFitCardSurface()
        .accessibilityElement(children: .combine)
    }
}
