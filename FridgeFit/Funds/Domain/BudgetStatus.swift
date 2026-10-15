import Foundation

/// A computed snapshot of how a budget is tracking, produced by
/// ``EvaluateBudgetStatusUseCase``.
struct BudgetStatus: Hashable, Sendable {
    let budget: FoodBudget
    let totalSpent: Money
    /// Budget limit minus total spent. Negative when the user has overspent.
    let remaining: Money
    let daysElapsed: Int
    let daysRemaining: Int
    /// The limit split evenly across the period.
    let dailyAllowance: Money
    /// What's left to spend today, given spending so far. Never below zero.
    let todayRemaining: Money
    /// Forecast end-of-period balance if spending keeps going at the current pace.
    /// Negative means the user is on track to overspend.
    let projectedEndBalance: Money

    /// Whether the user has already spent more than the limit.
    var hasOverspent: Bool { remaining.amount < 0 }

    /// Whether the current pace projects an overspend by the end of the period.
    var isProjectedToOverspend: Bool { projectedEndBalance.amount < 0 }
}


/// How much money is in the fridge and how much of it is about to be wasted,
/// produced by ``ValueFridgeUseCase``.
struct FridgeValuation: Hashable, Sendable {
    /// Total value of all priced items on hand.
    let totalValue: Money
    /// Value of priced items inside the expiry window.
    let atRiskValue: Money
    /// At-risk value spread over the days until the soonest of those items expires.
    let atRiskPerDay: Money
    let valuedItemCount: Int
    /// Items with no recorded cost — excluded from the totals above.
    let unvaluedItemCount: Int
}
