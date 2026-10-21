//
//  BuildImpactBudgetSummaryUseCase.swift
//  FridgeFit
//

import Foundation

/// Assembles the Profile → Impact & Budget screen's figures.
///
/// Pure and synchronous: it reads already-loaded stores and an already-loaded
/// event list, so every number it produces can be asserted in a unit test
/// with a fixed `now`. Loading is the view model's job (`ImpactBudgetViewModel`).
///
/// ## The two sources, kept apart
///
/// - **Activity log** (`InventoryEvent`) answers *how many* items were
///   finished or discarded. It carries no price.
/// - **FridgeFunds stores** answer *how much money*: the budget and its
///   spends, the per-item prices behind the fridge valuation, and the valued
///   waste records.
///
/// A discarded item can appear in both - once as an event, once as a
/// `WastedFoodCost`. They are never summed. The event count is used only to
/// report how much of the month's waste has a price attached at all.
struct BuildImpactBudgetSummaryUseCase {
    private let valueFridge: ValueFridgeUseCase
    private let evaluateBudget: EvaluateBudgetStatusUseCase
    private let budgetStore: BudgetStore

    init(valueFridge: ValueFridgeUseCase, evaluateBudget: EvaluateBudgetStatusUseCase, budgetStore: BudgetStore) {
        self.valueFridge = valueFridge
        self.evaluateBudget = evaluateBudget
        self.budgetStore = budgetStore
    }

    func execute(
        events: [InventoryEvent],
        currency: Currency,
        loadError: String? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ImpactBudgetSummary {
        let kitchen = KitchenImpactSummary.calculate(events: events, now: now, calendar: calendar)
        let budget = try? evaluateBudget.execute(now: now)

        // Totalled in the budget's own currency when there is a budget, so a
        // value-at-risk figure is never printed beside a limit it cannot be
        // compared with.
        let totalsCurrency = budget?.budget.currency ?? currency
        let valuation = valueFridge.execute(now: now, currency: totalsCurrency)

        return ImpactBudgetSummary(
            kitchen: kitchen,
            currency: totalsCurrency,
            budget: budget,
            valuation: valuation,
            atRiskIngredients: atRiskIngredients(now: now, calendar: calendar),
            waste: wasteReading(
                discardedThisMonth: kitchen.discardedThisMonth,
                currency: totalsCurrency,
                now: now,
                calendar: calendar
            ),
            loadError: loadError
        )
    }

    // MARK: - Value at risk

    private func atRiskIngredients(now: Date, calendar: Calendar) -> [AtRiskIngredient] {
        valueFridge.atRiskItems(now: now).compactMap { snapshot in
            // `atRiskItems` already excluded undated items, so a missing
            // state here would be a contradiction rather than a normal case.
            guard
                let days = snapshot.daysUntilExpiry(from: now),
                let state = ExpiryService.state(for: snapshot.expiryDate, now: now, calendar: calendar)
            else { return nil }

            return AtRiskIngredient(
                id: snapshot.id,
                name: snapshot.name,
                quantityText: Self.quantityText(snapshot.quantity, unit: snapshot.unit),
                expiryText: state.title,
                urgency: state.urgency,
                daysUntilExpiry: days,
                value: snapshot.lineValue,
                category: snapshot.category,
                unit: snapshot.unit
            )
        }
    }

    /// "1 bag", "200 g", "0.6 kg" - whole numbers lose the decimal point.
    static func quantityText(_ quantity: Double, unit: String) -> String {
        let rounded = (quantity * 100).rounded() / 100
        let amount = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%g", rounded)
        return unit.isEmpty ? amount : "\(amount) \(unit)"
    }

    // MARK: - Valued waste

    private func wasteReading(
        discardedThisMonth: Int,
        currency: Currency,
        now: Date,
        calendar: Calendar
    ) -> WasteCostReading {
        let costs = budgetStore.allWasteCosts().filter { $0.lostAmount.currency == currency }
        let thisMonth = costs.filter { calendar.isDate($0.discardedOn, equalTo: now, toGranularity: .month) }

        let lastMonthReference = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let lastMonth = costs.filter {
            calendar.isDate($0.discardedOn, equalTo: lastMonthReference, toGranularity: .month)
        }

        func total(_ records: [WastedFoodCost]) -> Money {
            records.reduce(Money.zero(in: currency)) { $0 + $1.lostAmount }
        }

        return WasteCostReading(
            thisMonth: total(thisMonth),
            lastMonth: total(lastMonth),
            recordCountThisMonth: thisMonth.count,
            unvaluedDiscardsThisMonth: max(0, discardedThisMonth - thisMonth.count)
        )
    }
}
