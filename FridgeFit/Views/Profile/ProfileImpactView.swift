//
//  ProfileImpactView.swift
//  FridgeFit
//

import SwiftUI

/// Profile → Impact & Budget.
///
/// Lays out the approved Fresh Botanical design for this screen: a filled
/// budget hero, four glanceable metrics, the Value at Risk list, the
/// household's most-finished staples, a four-week recovery chart with its
/// insight, and one primary action.
///
/// ## Where the figures come from
///
/// Two sources, deliberately kept apart and never added together:
///
/// - **FridgeFit's activity log** (`InventoryStore.events`) answers how many
///   items were finished or discarded. It holds no prices.
/// - **FridgeFunds** (`\.fundsEnvironment`) answers every money question:
///   the budget and its spends, and the per-item prices behind the fridge
///   valuation.
///
/// `BuildImpactBudgetSummaryUseCase` combines them. Anything neither source
/// can answer - CO₂e, "rescued before expiry", a saving figure - renders as
/// a stated unavailable state rather than a plausible-looking number.
struct ProfileImpactView: View {
    @ObservedObject var inventory: InventoryStore
    let onFindRecipes: () -> Void
    let onOpenPantry: () -> Void

    @StateObject private var viewModel: ImpactBudgetViewModel
    @State private var sheet: ImpactSheet?

    /// The funds environment is read from the SwiftUI environment at init so
    /// the view model can be a `@StateObject` and survive redraws. Reading
    /// it in `.task` instead would mean rebuilding the model every time the
    /// parent re-renders.
    init(
        inventory: InventoryStore,
        funds: FundsEnvironment?,
        onFindRecipes: @escaping () -> Void,
        onOpenPantry: @escaping () -> Void
    ) {
        self.inventory = inventory
        self.onFindRecipes = onFindRecipes
        self.onOpenPantry = onOpenPantry
        _viewModel = StateObject(wrappedValue: ImpactBudgetViewModel(funds: funds))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.section) {
            // A write that was refused and a load that failed are different
            // facts, and the write failure is the one with an action
            // attached, so it is titled for what it is rather than sharing
            // "Figures may be out of date".
            if let actionError = viewModel.actionError {
                ImpactCallout(
                    symbol: "exclamationmark.triangle.fill",
                    title: "Not saved",
                    message: actionError,
                    tone: .danger
                )
            } else if let message = viewModel.summary.loadError {
                ImpactCallout(
                    symbol: "exclamationmark.triangle.fill",
                    title: "Figures may be out of date",
                    message: message,
                    tone: .danger
                )
            } else if let pending = viewModel.pendingSyncNotice {
                // Durably stored, just not confirmed. Reported as
                // information, not as a problem - see `FundsWriteOutcome`.
                ImpactCallout(
                    symbol: "clock.arrow.2.circlepath",
                    title: "Waiting to sync",
                    message: pending,
                    tone: .neutral
                )
            }

            ImpactHeroCard(
                summary: viewModel.summary,
                onSetBudget: { sheet = .budget },
                onLogSpend: { sheet = .spend }
            )

            ImpactMetricGrid(summary: viewModel.summary)

            valueAtRiskSection
            finishedStaplesSection
            recoveryTrendSection
            primaryAction
        }
        .task {
            await inventory.load()
            await viewModel.refresh(events: inventory.events)
        }
        .onChange(of: inventory.events) { _, events in
            viewModel.recompute(events: events)
        }
        .onChange(of: inventory.items) { _, _ in
            Task { await viewModel.refresh(events: inventory.events) }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .budget:
                BudgetSetupSheet(
                    existing: viewModel.activeBudget,
                    defaultCurrency: viewModel.currency
                ) { limit, currency, cadence, startDate in
                    Task {
                        await viewModel.saveBudget(
                            limit: limit,
                            currency: currency,
                            cadence: cadence,
                            startDate: startDate,
                            events: inventory.events
                        )
                    }
                }
            case .spend:
                LogGrocerySpendSheet(currency: viewModel.currency) { amount, date, store in
                    Task {
                        await viewModel.logSpend(
                            amount: amount,
                            spentOn: date,
                            store: store,
                            events: inventory.events
                        )
                    }
                }
            case .price(let item):
                ItemPriceSheet(
                    itemName: item.name,
                    unit: item.unit,
                    quantityText: item.quantityText,
                    currency: viewModel.currency,
                    suggestion: viewModel.suggestedUnitCost(forIngredientNamed: item.name)
                ) { unitCost in
                    Task {
                        await viewModel.savePrice(
                            for: item,
                            unitCost: unitCost,
                            unit: item.unit,
                            events: inventory.events
                        )
                    }
                }
            }
        }
    }

    // MARK: - Value at Risk

    private var valueAtRiskSection: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            ImpactSectionHeading(title: "Value at Risk", symbol: "clock", tint: FridgeFitTheme.ColorToken.warningText) {
                Button(action: onOpenPantry) {
                    Label("Pantry audit", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                        .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens My Fridge")
            }

            if viewModel.summary.atRiskIngredients.isEmpty {
                ImpactCallout(symbol: "checkmark.circle.fill", title: nil, message: atRiskMessage, tone: .success)
            } else {
                ImpactCallout(symbol: "exclamationmark.circle.fill", title: nil, message: atRiskMessage)

                VStack(spacing: FridgeFitTheme.Spacing.small) {
                    ForEach(viewModel.summary.atRiskIngredients) { item in
                        AtRiskIngredientRow(
                            item: item,
                            onQuickCook: onFindRecipes,
                            onAddPrice: { sheet = .price(item) }
                        )
                    }
                }
            }
        }
    }

    /// The amber banner's sentence. Each branch states only what is actually
    /// known: a dollar figure appears only when at least one at-risk item
    /// carries a recorded price, and unpriced items are counted separately
    /// rather than silently dropped.
    private var atRiskMessage: String {
        let summary = viewModel.summary
        let items = summary.atRiskIngredients
        let window = ValueFridgeUseCase.atRiskWindowDays

        guard !items.isEmpty else {
            let stocked = (summary.valuation?.valuedItemCount ?? 0) + (summary.valuation?.unvaluedItemCount ?? 0)
            return stocked == 0
                ? "Add ingredients and their expiry dates in My Fridge, and anything approaching its date will be listed here."
                : "Nothing in your fridge is dated to expire in the next \(window) days."
        }

        let noun = items.count == 1 ? "item needs" : "items need"
        guard let value = summary.atRiskValue, let valuation = summary.valuation else {
            return "\(items.count) \(noun) attention in the next \(window) days. None of them has a recorded price, so there is no value to show yet."
        }

        let unpriced = valuation.atRiskUnvaluedCount
        let base = "\(valuation.atRiskItemCount) \(valuation.atRiskItemCount == 1 ? "item worth" : "items worth") \(value.formatted()) \(noun) attention. Cooking them within \(window) days keeps that money on your plate rather than in the bin."
        guard unpriced > 0 else { return base }
        return base + " \(unpriced) more \(unpriced == 1 ? "item is" : "items are") expiring without a recorded price."
    }

    // MARK: - Most finished staples

    private var finishedStaplesSection: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            ImpactSectionHeading(title: "Most Finished Staples", symbol: "leaf") {
                Text(verbatim: viewModel.summary.monthStart.formatted(.dateTime.month(.wide)))
                    .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
            }

            if viewModel.summary.kitchen.mostFinishedStaples.isEmpty {
                ImpactCallout(
                    symbol: "clock.arrow.circlepath",
                    title: nil,
                    message: "Nothing has been marked finished this month yet. Items you finish in My Fridge are listed here.",
                    tone: .neutral
                )
            } else {
                VStack(spacing: FridgeFitTheme.Spacing.small) {
                    ForEach(viewModel.summary.kitchen.mostFinishedStaples) { staple in
                        FinishedStapleRow(staple: staple)
                    }
                }
            }
        }
    }

    // MARK: - Recovery trend

    private var recoveryTrendSection: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.large) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly Recovery Trend")
                        .font(FridgeFitTheme.Typography.sectionTitleProminent)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    Text("Share of finished and discarded items that were finished")
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: FridgeFitTheme.Spacing.small)
                Label("Finished", systemImage: "circle.fill")
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .imageScale(.small)
                    .padding(.horizontal, FridgeFitTheme.Spacing.small)
                    .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
                    .background(FridgeFitTheme.ColorToken.disabledSurface, in: Capsule())
            }

            WeeklyRecoveryChart(points: viewModel.summary.kitchen.weeklyRecovery)

            ImpactCallout(symbol: "lightbulb.fill", title: "Budget saver insight", message: insightMessage)
        }
        .padding(FridgeFitTheme.Spacing.large)
        .fridgeFitCardSurface()
    }

    /// Composed only from figures that exist. No branch invents a saving, a
    /// target, or a projection the stores cannot support.
    private var insightMessage: String {
        let summary = viewModel.summary

        if let value = summary.atRiskValue, let valuation = summary.valuation {
            let items = "\(valuation.atRiskItemCount) expiring \(valuation.atRiskItemCount == 1 ? "ingredient" : "ingredients")"
            guard let budget = summary.budget else {
                return "Cooking your \(items) protects \(value.formatted()) of food you have already paid for."
            }
            if budget.hasOverspent {
                let over = Money(-budget.remaining.amount, budget.remaining.currency)
                return "You are \(over.formatted()) over this \(budget.budget.cadence.displayName.lowercased()) budget. Cooking your \(items) protects \(value.formatted()) you would otherwise need to replace."
            }
            return "Cooking your \(items) protects \(value.formatted()), on top of the \(budget.remaining.formatted()) still left in this \(budget.budget.cadence.displayName.lowercased()) budget."
        }

        if summary.waste.hasValuedWasteThisMonth {
            return "\(summary.waste.thisMonth.formatted()) of valued food was recorded as wasted this month. Prices you record make the figure above sharper."
        }

        if let percent = summary.kitchen.pantryEfficiencyPercent {
            let rounded = Int(percent.rounded())
            return "\(rounded)% of the items that left your kitchen this month were eaten rather than binned. Record prices in My Fridge to see what that is worth."
        }

        return "Mark items finished or discarded in My Fridge, and record what they cost, and this section will show what your cooking is worth."
    }

    // MARK: - Primary action

    private var primaryAction: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Button(action: onFindRecipes) {
                Label(ctaTitle, systemImage: "fork.knife")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FridgeFitPrimaryButtonStyle())
            .disabled(!viewModel.summary.hasAtRiskIngredients)
            .accessibilityHint("Opens personalised recipe recommendations")

            if !viewModel.summary.hasAtRiskIngredients {
                Text("Nothing is expiring soon, so there is nothing to plan around yet.")
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var ctaTitle: String {
        guard viewModel.summary.hasAtRiskIngredients else {
            return "Plan meals for expiring items"
        }
        guard let value = viewModel.summary.atRiskValue else {
            return "Plan meals for \(viewModel.summary.atRiskIngredients.count) expiring items"
        }
        return "Plan meals for expiring items (\(value.formatted()) at risk)"
    }
}

/// Which modal is open. A value rather than three booleans, so two sheets
/// can never be requested at once.
private enum ImpactSheet: Identifiable {
    case budget
    case spend
    case price(AtRiskIngredient)

    var id: String {
        switch self {
        case .budget: "budget"
        case .spend: "spend"
        case .price(let item): "price-\(item.id.rawValue)"
        }
    }
}

private struct FinishedStapleRow: View {
    let staple: FinishedStaple

    var body: some View {
        HStack(spacing: FridgeFitTheme.Spacing.medium) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 40, height: 40)
                .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
                .accessibilityHidden(true)

            Text(verbatim: staple.name)
                .font(FridgeFitTheme.Typography.cardTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: FridgeFitTheme.Spacing.small)

            FridgeFitStatusBadge(
                title: staple.timesFinished == 1 ? "Finished once" : "Finished \(staple.timesFinished) times",
                tone: .success
            )
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .frame(minHeight: 64)
        .fridgeFitCardSurface()
        .accessibilityElement(children: .combine)
    }
}

#Preview("With data") {
    ScrollView {
        ProfileImpactView(
            inventory: InventoryStore(
                pantryRepository: InMemoryPantryRepository(),
                eventRepository: InMemoryInventoryEventRepository()
            ),
            // Preview-only fixtures. Nothing in the shipping app can reach
            // these figures - see `FundsEnvironment.sample`.
            funds: .sample(),
            onFindRecipes: {},
            onOpenPantry: {}
        )
        .padding()
    }
    .background(FridgeFitTheme.ColorToken.canvas)
}

#Preview("Nothing recorded") {
    ScrollView {
        ProfileImpactView(
            inventory: InventoryStore(
                pantryRepository: InMemoryPantryRepository(),
                eventRepository: InMemoryInventoryEventRepository()
            ),
            funds: .inMemory(pantryRepository: InMemoryPantryRepository()),
            onFindRecipes: {},
            onOpenPantry: {}
        )
        .padding()
    }
    .background(FridgeFitTheme.ColorToken.canvas)
}
