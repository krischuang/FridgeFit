//
//  BudgetDashboardViewModel.swift
//  FridgeFit
//

import Foundation
import Observation

// drives the Budget Dashboard - current standing plus what's in the fridge.
// flips into a setup state when there's no budget yet.
@Observable
final class BudgetDashboardViewModel {
    private let environment: FundsEnvironment

    var status: BudgetStatus?
    var valuation: FridgeValuation?
    var hasNoBudget = false
    var errorMessage: String?

    init(environment: FundsEnvironment) {
        self.environment = environment
    }

    var currency: Currency { environment.budgetStore.activeBudget()?.currency ?? .aud }

    // loads fresh data from the stores first (Firestore in the real app), then recomputes
    func reload() async {
        await environment.reload()
        refresh()
    }

    func refresh(now: Date = Date()) {
        do {
            status = try environment.evaluateStatus.execute(now: now)
            hasNoBudget = false
        } catch EvaluateBudgetStatusUseCase.Failure.noActiveBudgetPeriod {
            status = nil
            hasNoBudget = true
        } catch {
            errorMessage = error.localizedDescription
        }
        if let loadError = environment.lastLoadError {
            errorMessage = loadError
        }
        valuation = environment.valueFridge.execute(now: now, currency: currency)
    }

    // creates the first budget and reloads
    func createBudget(limit: Decimal, cadence: BudgetCadence, now: Date = Date()) {
        let budget = FoodBudget(limit: Money(limit, currency), cadence: cadence, startDate: now)
        environment.budgetStore.saveBudget(budget)
        refresh(now: now)
    }
}
