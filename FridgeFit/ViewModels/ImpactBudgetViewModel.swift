//
//  ImpactBudgetViewModel.swift
//  FridgeFit
//

import Combine
import Foundation

/// State for Profile → Impact & Budget.
///
/// Owns the loading and nothing else: the arithmetic lives in
/// `BuildImpactBudgetSummaryUseCase`, which is pure and testable without a
/// view model at all.
///
/// `ObservableObject` rather than `@Observable` to match every other view
/// model in FridgeFit, so a screen can be handed this the same way
/// `ProfileView` is handed an `InventoryStore`.
@MainActor
final class ImpactBudgetViewModel: ObservableObject {
    @Published private(set) var summary: ImpactBudgetSummary
    @Published private(set) var isLoading = false
    /// Set when a write (saving a budget, logging a spend, saving a price)
    /// was rejected. Cleared on the next successful one.
    @Published var actionError: String?

    /// `nil` when FridgeFunds was never wired in - previews and tests that
    /// only care about the activity-log half. The money cards then render
    /// their unavailable state rather than zeroes.
    private let funds: FundsEnvironment?
    private let calendar: Calendar

    var isFundsAvailable: Bool { funds != nil }
    var activeBudget: FoodBudget? { funds?.budgetStore.activeBudget() }
    var currency: Currency { funds?.displayCurrency ?? .aud }

    init(funds: FundsEnvironment?, calendar: Calendar = .current, now: Date = .now) {
        self.funds = funds
        self.calendar = calendar
        self.summary = .empty(currency: funds?.displayCurrency ?? .aud, now: now)
    }

    /// Reloads the money stores, then recomputes everything from them plus
    /// the activity log the caller already has.
    ///
    /// `events` is passed in rather than fetched because `InventoryStore`
    /// already owns them - fetching again here would give the Profile screen
    /// a second, drifting copy of the same history.
    func refresh(events: [InventoryEvent], now: Date = .now) async {
        isLoading = true
        defer { isLoading = false }

        guard let funds else {
            summary = ImpactBudgetSummary(
                kitchen: KitchenImpactSummary.calculate(events: events, now: now, calendar: calendar),
                currency: .aud,
                budget: nil,
                valuation: nil,
                atRiskIngredients: [],
                waste: WasteCostReading(
                    thisMonth: .zero(in: .aud),
                    lastMonth: .zero(in: .aud),
                    recordCountThisMonth: 0,
                    unvaluedDiscardsThisMonth: 0
                ),
                loadError: nil
            )
            return
        }

        await funds.reload()
        recompute(events: events, now: now)
    }

    /// Recomputes from whatever the stores already hold, without a round
    /// trip. Used after a local write that has already updated them.
    func recompute(events: [InventoryEvent], now: Date = .now) {
        guard let funds else { return }
        let useCase = BuildImpactBudgetSummaryUseCase(
            valueFridge: funds.valueFridge,
            evaluateBudget: funds.evaluateStatus,
            budgetStore: funds.budgetStore
        )
        summary = useCase.execute(
            events: events,
            currency: funds.displayCurrency,
            loadError: funds.lastLoadError,
            now: now,
            calendar: calendar
        )
    }

    // MARK: - Writes

    /// Saves (or replaces) the user's food budget.
    func saveBudget(limit: Decimal, currency: Currency, cadence: BudgetCadence, startDate: Date, events: [InventoryEvent]) {
        guard let funds else { return }
        guard limit > 0 else {
            actionError = "Enter a budget greater than zero."
            return
        }
        funds.budgetStore.saveBudget(
            FoodBudget(limit: Money(limit, currency), cadence: cadence, startDate: calendar.startOfDay(for: startDate))
        )
        actionError = nil
        recompute(events: events)
    }

    /// Logs a grocery purchase against the active budget. Going over budget
    /// is not an error here - that is surfaced as a status, never a block.
    func logSpend(amount: Decimal, spentOn: Date, store: String?, events: [InventoryEvent]) {
        guard let funds else { return }
        do {
            try funds.recordSpend.execute(
                amount: Money(amount, funds.displayCurrency),
                spentOn: spentOn,
                store: store?.trimmingCharacters(in: .whitespacesAndNewlines).nilWhenEmpty
            )
            actionError = nil
            recompute(events: events)
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Records what one unit of an ingredient cost, so it can be valued.
    func savePrice(for item: AtRiskIngredient, unitCost: Decimal, unit: String, events: [InventoryEvent]) {
        guard let funds else { return }
        guard unitCost > 0 else {
            actionError = "Enter a price greater than zero."
            return
        }
        let money = Money(unitCost, funds.displayCurrency)
        let existing = funds.priceStore.info(for: item.id)
        funds.priceStore.save(
            ItemPriceInfo(pantryItemID: item.id, unitCost: money, expiryDate: existing?.expiryDate)
        )
        funds.rememberPrice(of: item.name, unit: unit, unitCost: money)
        actionError = nil
        recompute(events: events)
    }

    /// The last recorded price for an ingredient with this name, if the
    /// price book has one - so re-buying milk does not mean re-typing it.
    func suggestedUnitCost(forIngredientNamed name: String) -> Money? {
        funds?.priceBook.entry(forIngredientNamed: name)?.unitCost
    }
}

private extension String {
    var nilWhenEmpty: String? { isEmpty ? nil : self }
}

/// Reads a typed amount into a `Decimal`, for the editors that feed the
/// writes above.
///
/// Goes through `Decimal(string:locale:)` with the current locale so a
/// decimal comma is accepted where that is what the keyboard offers, and
/// falls back to the POSIX reading so "4.50" is never rejected either.
/// Deliberately not `Double`: money through a binary float is how 4.50
/// becomes 4.4999999.
enum DecimalInput {
    static func parse(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let localised = Decimal(string: trimmed, locale: .current) { return localised }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }
}
