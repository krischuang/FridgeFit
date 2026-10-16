//
//  LogSpendViewModel.swift
//  FridgeFit
//

import Foundation
import Observation

// drives the Log-a-Spend screen. going over budget is treated as a supportive
// warning, not an error - the spend always saves, the user just gets told where
// they now stand.
@Observable
final class LogSpendViewModel {
    private let environment: FundsEnvironment

    var amountText = ""
    var storeName = ""
    var spentOn = Date()

    var errorMessage: String?
    var warningMessage: String?
    var didSave = false

    init(environment: FundsEnvironment) {
        self.environment = environment
    }

    var currency: Currency { environment.budgetStore.activeBudget()?.currency ?? .aud }

    func save(now: Date = Date()) {
        errorMessage = nil
        warningMessage = nil
        didSave = false

        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: trimmed), value > 0 else {
            errorMessage = "Enter a spend amount greater than zero."
            return
        }

        do {
            try environment.recordSpend.execute(
                amount: Money(value, currency),
                spentOn: spentOn,
                store: storeName.isEmpty ? nil : storeName,
                now: now
            )
            didSave = true
            amountText = ""
            storeName = ""
            evaluateSupportiveWarning(now: now)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // after a successful save, check if they're over (or heading over) budget and
    // say so gently - never blocks the save itself
    private func evaluateSupportiveWarning(now: Date) {
        guard let status = try? environment.evaluateStatus.execute(now: now) else { return }
        let periodWord = status.budget.cadence == .weekly ? "week" : "fortnight"

        if status.hasOverspent {
            let over = Money(abs(status.remaining.amount), status.budget.currency).formatted()
            let days = status.daysRemaining
            warningMessage = "Heads up — you're \(over) over your \(status.budget.limit.formatted()) budget with \(days) day\(days == 1 ? "" : "s") to go. Still logged."
        } else if status.isProjectedToOverspend {
            let over = Money(abs(status.projectedEndBalance.amount), status.budget.currency).formatted()
            warningMessage = "At this pace you'll be about \(over) over by the end of the \(periodWord). Still logged."
        }
    }
}
