//
//  ImpactBudgetSummary.swift
//  FridgeFit
//

import Foundation

/// One line of the Value at Risk list.
///
/// Carries the money value as an optional rather than defaulting it to zero:
/// an ingredient with no recorded price is not worth nothing, it is simply
/// not priced, and the two must not render the same way.
struct AtRiskIngredient: Equatable, Sendable, Identifiable {
    let id: PantryItemID
    let name: String
    /// "1 bag", "200 g" - already formatted in the pantry's own unit.
    let quantityText: String
    /// "Expired", "Today", "Tomorrow", "2 days" - from `ExpiryService`, so
    /// this screen and My Fridge say the same thing about the same item.
    let expiryText: String
    let urgency: ExpiryUrgency
    let daysUntilExpiry: Int
    /// `nil` when the ingredient has no recorded unit cost.
    let value: Money?
    /// Drives the row's glyph, so the same food looks the same here as it
    /// does in My Fridge.
    let category: IngredientCategory
    /// The pantry's own unit symbol ("g", "L", "pcs"), kept so a price
    /// entered from this screen is recorded against the right unit.
    let unit: String
}

/// What the money side of the kitchen can say this month.
///
/// Waste cost and the discard count are two records of the same real-world
/// act, so they are never added together. The count is used only to say how
/// much of this month's waste carries a price at all.
struct WasteCostReading: Equatable, Sendable {
    let thisMonth: Money
    let lastMonth: Money
    /// How many `WastedFoodCost` records fell in the current month.
    let recordCountThisMonth: Int
    /// Items the activity log says were discarded this month that have no
    /// valued waste record. Shown as missing coverage, never as $0.
    let unvaluedDiscardsThisMonth: Int

    /// Change against last month, as a percentage of last month. `nil` when
    /// last month was zero - there is no percentage change from nothing.
    var monthOverMonthPercent: Double? {
        guard lastMonth.amount > 0 else { return nil }
        let delta = (thisMonth.amount - lastMonth.amount) / lastMonth.amount
        return NSDecimalNumber(decimal: delta * 100).doubleValue
    }

    /// Whether any valued waste exists this month. When false the screen
    /// says what is missing instead of printing `$0.00`.
    var hasValuedWasteThisMonth: Bool { recordCountThisMonth > 0 }
}

/// Everything the Profile → Impact & Budget screen renders.
///
/// Assembled by `BuildImpactBudgetSummaryUseCase` from two sources that stay
/// separate: FridgeFit's own activity log (`KitchenActivitySummary`) and the
/// FridgeFunds money stores. Each field below is either a recorded fact or
/// an explicit `nil`; nothing here is estimated to fill a gap in the design.
struct ImpactBudgetSummary: Equatable, Sendable {
    /// Counts, efficiency, streak and trend, from the activity log alone.
    let kitchen: KitchenActivitySummary
    /// The currency every `Money` on this screen is expressed in.
    let currency: Currency
    /// `nil` when the user has not set a food budget.
    let budget: BudgetStatus?
    /// `nil` when the pantry could not be read at all.
    let valuation: FridgeValuation?
    /// Everything expiring inside `ValueFridgeUseCase.atRiskWindowDays`,
    /// soonest first, priced and unpriced alike.
    let atRiskIngredients: [AtRiskIngredient]
    let waste: WasteCostReading
    /// Why the money figures may be stale, if the last load failed.
    let loadError: String?

    var monthStart: Date { kitchen.monthStart }

    /// Whether anything at all is expiring soon - drives the primary CTA's
    /// enabled state, so the button is never offered with nothing to plan.
    var hasAtRiskIngredients: Bool { !atRiskIngredients.isEmpty }

    /// At-risk value, but only when at least one at-risk item carries a
    /// price. Without that, `atRiskValue` is a true `$0.00` about a fridge
    /// that may well hold food worth rescuing, which would read as a claim.
    var atRiskValue: Money? {
        guard let valuation, valuation.atRiskItemCount > 0 else { return nil }
        return valuation.atRiskValue
    }

    /// An empty screen for a brand new account: nothing recorded anywhere.
    static func empty(currency: Currency = .aud, now: Date = .now) -> ImpactBudgetSummary {
        ImpactBudgetSummary(
            kitchen: KitchenActivitySummary.calculate(events: [], now: now),
            currency: currency,
            budget: nil,
            valuation: nil,
            atRiskIngredients: [],
            waste: WasteCostReading(
                thisMonth: .zero(in: currency),
                lastMonth: .zero(in: currency),
                recordCountThisMonth: 0,
                unvaluedDiscardsThisMonth: 0
            ),
            loadError: nil
        )
    }
}
