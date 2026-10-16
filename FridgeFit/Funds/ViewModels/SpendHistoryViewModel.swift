//
//  SpendHistoryViewModel.swift
//  FridgeFit
//

import Foundation
import Observation

// drives the Spend & Waste history screen - past spends, past waste, and the
// running total lost to waste
@Observable
final class SpendHistoryViewModel {
    private let environment: FundsEnvironment

    var spends: [GrocerySpend] = []
    var wasteCosts: [WastedFoodCost] = []
    var totalWasted: Money = .zero(in: .aud)

    init(environment: FundsEnvironment) {
        self.environment = environment
    }

    var currency: Currency { environment.budgetStore.activeBudget()?.currency ?? .aud }

    // loads fresh data from the stores first (Firestore in the real app), then recomputes
    func reload() async {
        await environment.reload()
        refresh()
    }

    func refresh() {
        let currency = self.currency
        spends = environment.budgetStore.allSpends().sorted { $0.spentOn > $1.spentOn }
        wasteCosts = environment.budgetStore.allWasteCosts().sorted { $0.discardedOn > $1.discardedOn }
        totalWasted = wasteCosts.reduce(Money.zero(in: currency)) { $0 + $1.lostAmount }
    }
}
