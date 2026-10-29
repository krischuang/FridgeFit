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
    ///
    /// This is now reachable for a *storage* failure, which it was not
    /// before: the stores returned `Void` and reported nothing, so the only
    /// thing that could populate this was client-side validation. A Firestore
    /// write refused for permissions updated the screen and logged a line.
    @Published var actionError: String?
    /// Set when a write is safely stored on the device but not yet confirmed
    /// by the server - Firestore's offline queue. Not an error, and not
    /// silence either. Cleared by the next committed write.
    @Published var pendingSyncNotice: String?
    /// True while a write is in flight, so the editors can disable Save
    /// instead of allowing a second identical write.
    @Published private(set) var isSaving = false

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
                kitchen: KitchenActivitySummary.calculate(events: events, now: now, calendar: calendar),
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

    /// Runs one write, reports what really happened, and recomputes.
    ///
    /// Every write below shares this, so none of them can accidentally grow
    /// its own definition of "saved". The rules, in one place:
    ///
    /// - A thrown error becomes `actionError` and **nothing is recomputed**,
    ///   because the store rolled its change back and the summary on screen
    ///   is still the correct one.
    /// - `.pendingSync` becomes `pendingSyncNotice`, not an error: the write
    ///   is durable, just unconfirmed. The summary *is* recomputed, since the
    ///   store has applied it locally.
    /// - `.committed` clears both notices.
    ///
    /// `isSaving` is held for the duration so Save can be disabled rather
    /// than tapped twice. A repeat is harmless at the store level anyway -
    /// every write is keyed by id, so a retry overwrites one document - but
    /// two in flight would still produce two spinners and one confusing
    /// error.
    private func perform(
        events: [InventoryEvent],
        _ write: () async throws -> FundsWriteOutcome
    ) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            let outcome = try await write()
            actionError = nil
            pendingSyncNotice = outcome.statusDescription
            recompute(events: events)
        } catch {
            pendingSyncNotice = nil
            actionError = Self.message(for: error)
        }
    }

    /// Storage failures arrive as framework errors. The two the user can act
    /// on are named; the rest are reported as a retryable save failure
    /// rather than as Firestore's own wording.
    private static func message(for error: Error) -> String {
        if let error = error as? PantryRepositoryError, error == .notAuthenticated {
            return "You're signed out, so this couldn't be saved. Sign in and try again."
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "That couldn't be saved. Please try again."
    }

    /// Saves (or replaces) the user's food budget.
    func saveBudget(
        limit: Decimal,
        currency: Currency,
        cadence: BudgetCadence,
        startDate: Date,
        events: [InventoryEvent]
    ) async {
        guard let funds else { return }
        guard limit > 0 else {
            actionError = "Enter a budget greater than zero."
            return
        }
        let budget = FoodBudget(
            limit: Money(limit, currency),
            cadence: cadence,
            startDate: calendar.startOfDay(for: startDate)
        )
        await perform(events: events) {
            try await funds.budgetStore.saveBudget(budget)
        }
    }

    /// Logs a grocery purchase against the active budget. Going over budget
    /// is not an error here - that is surfaced as a status, never a block.
    func logSpend(amount: Decimal, spentOn: Date, store: String?, events: [InventoryEvent]) async {
        guard let funds else { return }
        let storeName = store?.trimmingCharacters(in: .whitespacesAndNewlines).nilWhenEmpty
        await perform(events: events) {
            try await funds.recordSpend.execute(
                amount: Money(amount, funds.displayCurrency),
                spentOn: spentOn,
                store: storeName
            ).outcome
        }
    }

    /// Records what one unit of an ingredient cost, so it can be valued.
    ///
    /// Two writes, and the second is not allowed to hide a failure of the
    /// first. The item price is what makes the fridge valuation work, so it
    /// goes first; the price book is a convenience for next time. If the
    /// price book write fails after the item price succeeded, the user is
    /// told - the price *is* recorded, and claiming otherwise would be as
    /// wrong as the reverse.
    func savePrice(for item: AtRiskIngredient, unitCost: Decimal, unit: String, events: [InventoryEvent]) async {
        guard let funds else { return }
        guard unitCost > 0 else {
            actionError = "Enter a price greater than zero."
            return
        }
        let money = Money(unitCost, funds.displayCurrency)
        let existing = funds.priceStore.info(for: item.id)
        let name = item.name

        await perform(events: events) {
            let priced = try await funds.priceStore.save(
                ItemPriceInfo(pantryItemID: item.id, unitCost: money, expiryDate: existing?.expiryDate)
            )
            let remembered = try await funds.rememberPrice(of: name, unit: unit, unitCost: money)
            // The weaker of the two: if either is only queued, the pair is
            // only queued.
            return priced == .committed && remembered == .committed ? .committed : .pendingSync
        }
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
