//
//  ImpactBudgetComponents.swift
//  FridgeFit
//
//  The building blocks of Profile → Impact & Budget, laid out to match the
//  approved Fresh Botanical design for that screen. Each one takes finished
//  figures and renders them; none of them calculates anything, so a card can
//  never disagree with the summary it was handed.
//

import SwiftUI

// MARK: - Hero

/// The filled green summary at the top of the screen: the period's budget
/// headline, what left the kitchen, the spend bar and two supporting chips.
struct ImpactHeroCard: View {
    let summary: ImpactBudgetSummary
    let onSetBudget: () -> Void
    let onLogSpend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            titleRow
            headlineRow
            budgetProgress
            chipRow
        }
        .padding(FridgeFitTheme.Spacing.xLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroBackground)
        .clipShape(RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.largeCard, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    private var heroBackground: some View {
        ZStack(alignment: .topTrailing) {
            FridgeFitTheme.ColorToken.brandFill
            Image(systemName: "wallet.bifold.fill")
                .font(.system(size: 104))
                .foregroundStyle(.white.opacity(0.08))
                .offset(x: -24, y: -8)
                .accessibilityHidden(true)
            Circle()
                .fill(.white.opacity(0.07))
                .frame(width: 150, height: 150)
                .offset(x: 48, y: 150)
                .accessibilityHidden(true)
        }
        .allowsHitTesting(false)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: "\(monthName) Impact & Budget")
                .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: FridgeFitTheme.Spacing.small)
            Label(status.title, systemImage: status.symbol)
                .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, FridgeFitTheme.Spacing.small)
                .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
                .background(.white.opacity(0.2), in: Capsule())
        }
        .accessibilityElement(children: .combine)
    }

    private var headlineRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: FridgeFitTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: FridgeFitTheme.Spacing.xSmall) {
                    Text(verbatim: headline.value)
                        .font(FridgeFitTheme.Typography.hero)
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(verbatim: headline.caption)
                        .font(FridgeFitTheme.Typography.supporting.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                if let detail = headline.detail {
                    Text(verbatim: detail)
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(headline.accessibility)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: "\(summary.kitchen.finishedThisMonth) items")
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(.white)
                Text("Finished this month")
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(summary.kitchen.finishedThisMonth) items finished this month")
        }
        .padding(.top, FridgeFitTheme.Spacing.xSmall)
    }

    @ViewBuilder
    private var budgetProgress: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            if let budget = summary.budget {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: "\(budget.budget.cadence.displayName) grocery budget")
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(.white)
                    Spacer(minLength: FridgeFitTheme.Spacing.small)
                    HStack(spacing: 3) {
                        Text(verbatim: budget.totalSpent.formatted())
                            .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(verbatim: "of \(budget.budget.limit.formatted())")
                            .font(FridgeFitTheme.Typography.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(budget.budget.cadence.displayName) grocery budget, \(budget.totalSpent.formatted()) spent of \(budget.budget.limit.formatted())")
                ProgressBar(fraction: Self.spentFraction(budget))
                Button(action: onLogSpend) {
                    Label("Log a grocery spend", systemImage: "plus.circle")
                        .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 32)
            } else {
                Text("No food budget set, so spending cannot be tracked yet.")
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onSetBudget) {
                    Label("Set a food budget", systemImage: "arrow.right")
                        .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 32)
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
        .padding(.top, FridgeFitTheme.Spacing.xSmall)
    }

    private var chipRow: some View {
        FlowLayout(spacing: FridgeFitTheme.Spacing.small) {
            HeroChip(symbol: "speedometer", text: efficiencyChipText)
            HeroChip(symbol: "leaf", text: "CO₂e prevented not tracked")
        }
        .padding(.top, FridgeFitTheme.Spacing.xSmall)
    }

    // MARK: Derived text

    /// `budget.totalSpent / budget.limit`, clamped. The limit is validated
    /// positive when the budget is saved, so the guard is belt and braces.
    static func spentFraction(_ status: BudgetStatus) -> Double {
        let limit = NSDecimalNumber(decimal: status.budget.limit.amount).doubleValue
        guard limit > 0 else { return 0 }
        let spent = NSDecimalNumber(decimal: status.totalSpent.amount).doubleValue
        return min(max(spent / limit, 0), 1)
    }

    private var monthName: String {
        summary.monthStart.formatted(.dateTime.month(.wide))
    }

    private var efficiencyChipText: String {
        guard let percent = summary.kitchen.pantryEfficiencyPercent else {
            return "Pantry efficiency needs an outcome logged"
        }
        return "\(Int(percent.rounded()))% of items eaten, not binned"
    }

    private struct Headline {
        let value: String
        let caption: String
        let detail: String?
        let accessibility: String
    }

    private var headline: Headline {
        guard let budget = summary.budget else {
            return Headline(
                value: "—",
                caption: "no budget",
                detail: "Set a budget to see what is left this period.",
                accessibility: "No food budget set"
            )
        }
        let period = budget.budget.cadence == .weekly ? "this week" : "this fortnight"
        if budget.hasOverspent {
            let over = Money(-budget.remaining.amount, budget.remaining.currency)
            return Headline(
                value: over.formatted(),
                caption: "over budget",
                detail: "\(budget.daysRemaining) days left in this period.",
                accessibility: "\(over.formatted()) over budget \(period)"
            )
        }
        return Headline(
            value: budget.remaining.formatted(),
            caption: "left \(period)",
            detail: "\(budget.todayRemaining.formatted()) of today's allowance remains.",
            accessibility: "\(budget.remaining.formatted()) left \(period)"
        )
    }

    private var status: (title: LocalizedStringKey, symbol: String) {
        guard let budget = summary.budget else { return ("No budget set", "creditcard") }
        if budget.hasOverspent { return ("Over budget", "exclamationmark.triangle.fill") }
        if budget.isProjectedToOverspend { return ("Pace is high", "chart.line.uptrend.xyaxis") }
        return ("On track", "checkmark.seal.fill")
    }
}

private struct HeroChip: View {
    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(FridgeFitTheme.ColorToken.honey)
        }
        .font(FridgeFitTheme.Typography.caption.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, FridgeFitTheme.Spacing.medium)
        .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
        .background(.white.opacity(0.15), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule()
                    .fill(FridgeFitTheme.ColorToken.honey)
                    .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 6 : 0))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

// MARK: - Metric grid

/// The four glanceable cards under the hero.
struct ImpactMetricGrid: View {
    let summary: ImpactBudgetSummary

    private let columns = [
        GridItem(.flexible(), spacing: FridgeFitTheme.Spacing.small),
        GridItem(.flexible(), spacing: FridgeFitTheme.Spacing.small)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: FridgeFitTheme.Spacing.small) {
            ImpactMetricCard(
                symbol: "wallet.bifold",
                tone: .neutral,
                badge: spendBadge,
                value: spentValue,
                caption: "Spent this period"
            )
            ImpactMetricCard(
                symbol: "exclamationmark.triangle",
                tone: .warning,
                badge: atRiskBadge,
                value: atRiskValue,
                caption: "At risk (expiring soon)"
            )
            ImpactMetricCard(
                symbol: "shippingbox",
                tone: .success,
                badge: nil,
                value: "\(summary.kitchen.finishedThisMonth) items",
                caption: "Finished this month"
            )
            ImpactMetricCard(
                symbol: "flame",
                tone: .warning,
                badge: nil,
                value: streakValue,
                caption: "Zero-waste streak"
            )
        }
    }

    private var spentValue: String {
        summary.budget?.totalSpent.formatted() ?? "Not tracked"
    }

    private var spendBadge: String? {
        guard let budget = summary.budget else { return nil }
        let percent = ImpactHeroCard.spentFraction(budget) * 100
        return "\(Int(percent.rounded()))% of limit"
    }

    private var atRiskValue: String {
        guard let value = summary.atRiskValue else { return "Not priced" }
        return value.formatted()
    }

    private var atRiskBadge: String? {
        let total = summary.atRiskIngredients.count
        guard total > 0 else { return nil }
        return total == 1 ? "1 item" : "\(total) items"
    }

    private var streakValue: String {
        guard let weeks = summary.kitchen.zeroWasteStreakWeeks else { return "No history" }
        return weeks == 1 ? "1 week" : "\(weeks) weeks"
    }
}

private struct ImpactMetricCard: View {
    enum Tone { case neutral, success, warning }

    let symbol: String
    let tone: Tone
    let badge: String?
    let value: String
    let caption: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
            HStack(alignment: .top) {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(iconForeground)
                    .frame(width: 32, height: 32)
                    .background(iconBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))
                Spacer(minLength: FridgeFitTheme.Spacing.xSmall)
                if let badge {
                    Text(verbatim: badge)
                        .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(iconForeground)
                        .multilineTextAlignment(.trailing)
                }
            }
            Spacer(minLength: FridgeFitTheme.Spacing.xSmall)
            Text(verbatim: value)
                .font(FridgeFitTheme.Typography.cardTitle)
                .foregroundStyle(tone == .warning ? FridgeFitTheme.ColorToken.warningText : FridgeFitTheme.ColorToken.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
            Text(caption)
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
        .accessibilityElement(children: .combine)
    }

    private var iconForeground: Color {
        switch tone {
        case .neutral, .success: return FridgeFitTheme.ColorToken.primary
        case .warning: return FridgeFitTheme.ColorToken.warningText
        }
    }

    private var iconBackground: Color {
        switch tone {
        case .neutral, .success: return FridgeFitTheme.ColorToken.successBackground
        case .warning: return FridgeFitTheme.ColorToken.warningBackground
        }
    }
}

// MARK: - Section header

struct ImpactSectionHeading<Trailing: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    var tint: Color = FridgeFitTheme.ColorToken.primary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label {
                Text(title)
                    .font(FridgeFitTheme.Typography.sectionTitleProminent)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            Spacer(minLength: FridgeFitTheme.Spacing.small)
            trailing
        }
    }
}

// MARK: - Value at risk

/// One expiring ingredient, with its urgency stripe, amount and value.
struct AtRiskIngredientRow: View {
    let item: AtRiskIngredient
    let onQuickCook: () -> Void
    let onAddPrice: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(stripe)
                .frame(width: 4)
                .accessibilityHidden(true)

            HStack(spacing: FridgeFitTheme.Spacing.medium) {
                IngredientArtwork(category: item.category, size: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.name)
                        .font(FridgeFitTheme.Typography.cardTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                        .lineLimit(1)
                    Text(verbatim: "\(item.expiryText) • \(item.quantityText)")
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(item.urgency.rawValue >= ExpiryUrgency.tomorrow.rawValue
                            ? FridgeFitTheme.ColorToken.warningText
                            : FridgeFitTheme.ColorToken.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: FridgeFitTheme.Spacing.small)

                VStack(alignment: .trailing, spacing: 2) {
                    if let value = item.value {
                        Text(verbatim: value.formatted())
                            .font(FridgeFitTheme.Typography.cardTitle)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                        Button("Quick cook", action: onQuickCook)
                            .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                            .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                            .buttonStyle(.plain)
                    } else {
                        Text("No price")
                            .font(FridgeFitTheme.Typography.caption)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        Button("Add price", action: onAddPrice)
                            .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                            .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(FridgeFitTheme.Spacing.medium)
        }
        .frame(minHeight: 72)
        .fridgeFitCardSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let money = item.value.map { ", worth \($0.formatted())" } ?? ", no recorded price"
        return "\(item.name), \(item.quantityText), \(item.expiryText)\(money)"
    }

    private var stripe: Color {
        switch item.urgency {
        case .expired, .today: return FridgeFitTheme.ColorToken.accent
        case .tomorrow: return FridgeFitTheme.ColorToken.honey
        default: return FridgeFitTheme.ColorToken.primaryMuted
        }
    }
}

// MARK: - Callouts

/// The amber "needs attention" banner and the lightbulb insight both use
/// this, so one change moves both.
struct ImpactCallout: View {
    let symbol: String
    let title: LocalizedStringKey?
    let message: String
    var tone: FridgeFitStatusTone = .warning

    var body: some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.medium) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(foreground)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title)
                        .font(FridgeFitTheme.Typography.caption.weight(.bold))
                        .foregroundStyle(foreground)
                }
                Text(verbatim: message)
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous)
                .stroke(foreground.opacity(0.2), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var foreground: Color {
        switch tone {
        case .warning: return FridgeFitTheme.ColorToken.warningText
        case .success: return FridgeFitTheme.ColorToken.primary
        case .danger: return FridgeFitTheme.ColorToken.danger
        case .neutral: return FridgeFitTheme.ColorToken.textSecondary
        }
    }

    private var background: Color {
        switch tone {
        case .warning: return FridgeFitTheme.ColorToken.warningBackground
        case .success: return FridgeFitTheme.ColorToken.successBackground
        case .danger: return FridgeFitTheme.ColorToken.errorBackground
        case .neutral: return FridgeFitTheme.ColorToken.disabledSurface
        }
    }
}

// MARK: - Recovery trend

/// The four-week bar chart.
///
/// A week with no recorded outcome draws an empty track labelled "—". It is
/// not a zero: nothing was measured, and a zero-height bar would read as a
/// week in which everything was thrown away.
struct WeeklyRecoveryChart: View {
    let points: [WeeklyRecoveryPoint]

    private let barHeight: CGFloat = 120

    var body: some View {
        HStack(alignment: .bottom, spacing: FridgeFitTheme.Spacing.medium) {
            ForEach(points) { point in
                VStack(spacing: FridgeFitTheme.Spacing.xSmall) {
                    Text(verbatim: point.percent.map { "\(Int($0.rounded()))%" } ?? "—")
                        .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(point.percent == nil
                            ? FridgeFitTheme.ColorToken.textSecondary
                            : FridgeFitTheme.ColorToken.textPrimary)

                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous)
                            .fill(FridgeFitTheme.ColorToken.disabledSurface)
                            .frame(height: barHeight)
                        if let percent = point.percent {
                            RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous)
                                .fill(percent >= 90 ? FridgeFitTheme.ColorToken.primary : FridgeFitTheme.ColorToken.primaryMuted)
                                .frame(height: max(barHeight * percent / 100, 4))
                        }
                    }
                    .frame(height: barHeight)

                    Text(verbatim: point.label)
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label(for: point))
            }
        }
    }

    private func label(for point: WeeklyRecoveryPoint) -> String {
        guard let percent = point.percent else {
            return "\(point.label), no outcomes recorded"
        }
        return "\(point.label), \(Int(percent.rounded())) percent, \(point.finished) finished and \(point.discarded) discarded"
    }
}
