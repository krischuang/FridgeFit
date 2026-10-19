import SwiftUI

struct ProfileImpactView: View {
    @ObservedObject var inventory: InventoryStore
    let onFindRecipes: () -> Void

    @State private var summary = KitchenImpactSummary.calculate(events: [])

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.section) {
            ImpactSectionHeader()
            ImpactProgressHero(summary: summary)
            ImpactSummaryCards(summary: summary)
            RescuedStaplesEmptyState()
            RecoveryTrendEmptyState()
            WasteReductionTip(items: expiringItems)
            Button(action: onFindRecipes) {
                Label("Find recipes for expiring items", systemImage: "fork.knife")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FridgeFitPrimaryButtonStyle())
            .accessibilityHint("Opens personalised recipe recommendations")
        }
        .task {
            await inventory.load()
            refreshSummary()
        }
        .onChange(of: inventory.events) { _, _ in refreshSummary() }
    }

    private var expiringItems: [PantryItem] {
        inventory.useFirstItems()
    }

    private func refreshSummary() {
        summary = KitchenImpactSummary.calculate(events: inventory.events)
    }
}

private struct ImpactSectionHeader: View {
    var body: some View {
        HStack(spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: "leaf.fill")
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 36, height: 36)
                .background(FridgeFitTheme.ColorToken.successBackground, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Profile & Metrics")
                    .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .textCase(.uppercase)
                Text("Kitchen Impact")
                    .font(FridgeFitTheme.Typography.screenTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ImpactProgressHero: View {
    let summary: KitchenImpactSummary

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text("This Month's Progress")
                    .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
                Spacer()
                Label(summary.monthStart.formatted(.dateTime.month(.abbreviated).year()), systemImage: "calendar")
                    .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                    .padding(.horizontal, FridgeFitTheme.Spacing.small)
                    .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
                    .background(Color.white.opacity(0.16), in: Capsule())
            }

            Text("Impact not tracked yet")
                .font(FridgeFitTheme.Typography.screenTitle)
                .foregroundStyle(.white)

            Text("FridgeFit records finished and discarded items, but rescue impact needs expiry-at-use, cost, and emissions data that is not collected yet.")
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(Color.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: FridgeFitTheme.Spacing.small) {
                ImpactActivityBadge(value: summary.finishedThisMonth, label: "finished")
                ImpactActivityBadge(value: summary.discardedThisMonth, label: "discarded")
            }
        }
        .padding(FridgeFitTheme.Spacing.xLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FridgeFitTheme.ColorToken.primary, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.largeCard, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ImpactActivityBadge: View {
    let value: Int
    let label: String

    var body: some View {
        Text(verbatim: "\(value) \(label)")
            .font(FridgeFitTheme.Typography.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, FridgeFitTheme.Spacing.small)
            .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
            .background(Color.white.opacity(0.16), in: Capsule())
    }
}

private struct ImpactSummaryCards: View {
    let summary: KitchenImpactSummary

    private let columns = [GridItem(.adaptive(minimum: 98), spacing: FridgeFitTheme.Spacing.small)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            ImpactMetricCard(title: "Saved on groceries", systemImage: "wallet.bifold", value: unavailable(summary.grocerySavings))
            ImpactMetricCard(title: "Items rescued in time", systemImage: "shippingbox", value: unavailable(summary.rescuedItems))
            ImpactMetricCard(title: "Zero-waste streak", systemImage: "flame", value: unavailable(summary.zeroWasteStreakWeeks))
        }
    }

    private func unavailable<T>(_ value: T?) -> String {
        value == nil ? "Not tracked" : "Available"
    }
}

private struct ImpactMetricCard: View {
    let title: String
    let systemImage: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: systemImage)
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 32, height: 32)
                .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small))
            Text(verbatim: value)
                .font(FridgeFitTheme.Typography.cardTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            Text(verbatim: title)
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
        .accessibilityElement(children: .combine)
    }
}

private struct RescuedStaplesEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Label("Frequently Rescued Staples", systemImage: "leaf")
                .font(FridgeFitTheme.Typography.sectionTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            ImpactEmptyCard(
                systemImage: "clock.arrow.circlepath",
                title: "No rescue history yet",
                message: "Future expiry-aware use history will show which staples you rescue most often."
            )
        }
    }
}

private struct RecoveryTrendEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            Text("Weekly Recovery Trend")
                .font(FridgeFitTheme.Typography.sectionTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            Text("Percentage of perishable ingredients used before expiry")
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            HStack(alignment: .bottom, spacing: FridgeFitTheme.Spacing.medium) {
                ForEach(1...4, id: \.self) { week in
                    VStack(spacing: FridgeFitTheme.Spacing.small) {
                        RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small)
                            .fill(FridgeFitTheme.ColorToken.disabledSurface)
                            .frame(height: 44)
                        Text("W\(week)")
                            .font(FridgeFitTheme.Typography.caption)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("A trend will appear when expiry-at-use outcomes can be measured.")
                .font(FridgeFitTheme.Typography.metadata)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        }
        .padding(FridgeFitTheme.Spacing.large)
        .fridgeFitCardSurface()
        .accessibilityElement(children: .combine)
    }
}

private struct ImpactEmptyCard: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.medium) {
            Image(systemName: systemImage)
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 40, height: 40)
                .background(FridgeFitTheme.ColorToken.successBackground, in: Circle())
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Text(title).font(FridgeFitTheme.Typography.cardTitle)
                Text(message)
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(FridgeFitTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fridgeFitCardSurface()
        .accessibilityElement(children: .combine)
    }
}

private struct WasteReductionTip: View {
    let items: [PantryItem]

    var body: some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.medium) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Text(items.isEmpty ? "Waste-Reduction Tip" : "Use First")
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text(message)
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(FridgeFitTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FridgeFitTheme.ColorToken.warningBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card))
        .accessibilityElement(children: .combine)
    }

    private var message: String {
        guard !items.isEmpty else {
            return "Plan one flexible meal each week around the ingredients expiring first."
        }
        let names = items.prefix(3).map(\.name).formatted(.list(type: .and))
        return "Your current expiry data suggests using \(names) first."
    }
}
