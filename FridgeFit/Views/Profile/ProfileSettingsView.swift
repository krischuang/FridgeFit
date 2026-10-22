import FirebaseAuth
import SwiftUI

struct ProfileSettingsView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    let store: ProfileSettingsStoring
    @State private var settings = ProfileSettings()

    init(store: ProfileSettingsStoring = UserDefaultsProfileSettingsStore()) {
        self.store = store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.section) {
            SettingsSectionTitle(title: "Expiry & Notifications", systemImage: "bell.badge")
            SettingsCard {
                UnsupportedSettingsRow(
                    title: "Expiry reminders",
                    detail: "Notification scheduling is not available in this build",
                    systemImage: "alarm",
                    tone: .warning
                )
                SettingsDivider()
                UnsupportedSettingsRow(
                    title: "Alert timing",
                    detail: "Available after expiry notifications are implemented",
                    systemImage: "clock"
                )
                SettingsDivider()
                UnsupportedSettingsRow(
                    title: "Sunday meal prep prompt",
                    detail: "Weekly notification scheduling is not available",
                    systemImage: "calendar"
                )
            }

            SettingsSectionTitle(title: "Storage & Pantry Behaviour", systemImage: "cabinet")
            SettingsCard {
                UnsupportedSettingsRow(
                    title: "Default quick-add shelf",
                    detail: "Choose storage when adding each item",
                    systemImage: "refrigerator"
                )
                SettingsDivider()
                UnsupportedSettingsRow(
                    title: "Auto-deduct cooked items",
                    detail: "Inventory changes still require confirmation",
                    systemImage: "cart.badge.minus"
                )
                SettingsDivider()
                UnsupportedSettingsRow(
                    title: "Smart Scan auto-match",
                    detail: "Review detected ingredients before saving",
                    systemImage: "viewfinder"
                )
            }

            SettingsSectionTitle(title: "Kitchen & Units", systemImage: "ruler")
            SettingsCard {
                MeasurementPreferenceRow(selection: $settings.measurementSystem)
                SettingsDivider()
                ServingPreferenceRow(servings: $settings.defaultServingSize)
            }

            SettingsSectionTitle(title: "Data & Account", systemImage: "person.crop.circle")
            SettingsCard {
                SettingsStatusRow(
                    title: "Sync status",
                    detail: "Private, user-scoped cloud storage",
                    systemImage: "cloud",
                    status: "Firestore account sync"
                )
                SettingsDivider()
                UnsupportedSettingsRow(
                    title: "Export kitchen data",
                    detail: "Secure export is not available yet",
                    systemImage: "square.and.arrow.up"
                )
                SettingsDivider()
                UnsupportedSettingsRow(
                    title: "Clear pantry data",
                    detail: "Bulk deletion is disabled until an atomic, verified workflow exists",
                    systemImage: "trash",
                    tone: .danger
                )
            }

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
        }
        .task { settings = store.load() }
        .onChange(of: settings) { _, newValue in store.save(newValue) }
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

private struct UnsupportedSettingsRow: View {
    let title: String
    let detail: String
    let systemImage: String
    var tone: SettingsRowTone = .neutral

    var body: some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.medium) {
            SettingsRowIcon(systemImage: systemImage, tone: tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(tone == .danger ? FridgeFitTheme.ColorToken.danger : FridgeFitTheme.ColorToken.textPrimary)
                Text(verbatim: detail)
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Unavailable")
                    .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(FridgeFitTheme.Spacing.large)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .opacity(0.78)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(title), unavailable"))
    }
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
