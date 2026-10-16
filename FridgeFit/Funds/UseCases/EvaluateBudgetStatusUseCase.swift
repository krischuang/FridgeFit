//
//  EvaluateBudgetStatusUseCase.swift
//  FridgeFit
//

import Foundation

// Works out how the user's food spending is tracking against their budget: how
// much is left, how much can still be spent today, and — at the current pace —
// whether they're heading for an overspend before the period ends. This forecast
// is what powers the app's supportive over-budget warning, never a hard block.
struct EvaluateBudgetStatusUseCase {
    let budgetStore: BudgetStore

    // Failures that stop a status from being computed.
    enum Failure: LocalizedError, Equatable {
        // No budget has been set, so there is nothing to evaluate.
        case noActiveBudgetPeriod

        var errorDescription: String? {
            switch self {
            case .noActiveBudgetPeriod:
                return "Set a food budget to see how your spending is tracking."
            }
        }
    }

    // Computes the current budget status.
    // - Parameter now: the reference "today" (injectable for testing).
    // - Throws: ``Failure/noActiveBudgetPeriod`` when no budget is set.
    func execute(now: Date = Date()) throws -> BudgetStatus {
        guard let budget = budgetStore.activeBudget() else {
            throw Failure.noActiveBudgetPeriod
        }

        let currency = budget.currency
        let calendar = Calendar.current
        let totalDays = budget.cadence.lengthInDays

        // only spends inside the current period count towards it
        let inPeriodSpends = budgetStore.allSpends().filter { budget.contains($0.spentOn) }
        let totalSpent = inPeriodSpends.reduce(Money.zero(in: currency)) { $0 + $1.amount }
        let remaining = budget.limit - totalSpent

        // today counts as day 1, clamped so it can't go past the period length
        let startDay = calendar.startOfDay(for: budget.startDate)
        let today = calendar.startOfDay(for: now)
        let elapsedRaw = (calendar.dateComponents([.day], from: startDay, to: today).day ?? 0) + 1
        let daysElapsed = min(max(elapsedRaw, 1), totalDays)
        let daysRemaining = max(0, totalDays - daysElapsed)

        let dailyAllowance = budget.dailyAllowance

        // today's remaining = flat daily allowance minus whatever's already spent today
        let spentToday = inPeriodSpends
            .filter { calendar.isDate($0.spentOn, inSameDayAs: now) }
            .reduce(Money.zero(in: currency)) { $0 + $1.amount }
        let todayRemainingRaw = dailyAllowance - spentToday
        let todayRemaining = todayRemainingRaw.amount < 0 ? Money.zero(in: currency) : todayRemainingRaw

        // forecast end-of-period balance if spending keeps going at the current average pace
        let averagePerDay = totalSpent.dividedEvenly(by: daysElapsed)
        let projectedTotal = averagePerDay.scaled(by: Decimal(totalDays))
        let projectedEndBalance = budget.limit - projectedTotal

        return BudgetStatus(
            budget: budget,
            totalSpent: totalSpent,
            remaining: remaining,
            daysElapsed: daysElapsed,
            daysRemaining: daysRemaining,
            dailyAllowance: dailyAllowance,
            todayRemaining: todayRemaining,
            projectedEndBalance: projectedEndBalance
        )
    }
}
