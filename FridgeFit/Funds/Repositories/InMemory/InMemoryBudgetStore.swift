//
//  InMemoryBudgetStore.swift
//  FridgeFit
//

import Foundation

// in-memory BudgetStore for the assignment - nothing survives relaunch. a
// SwiftData-backed version can replace this at group integration since everything
// depends on the BudgetStore protocol, not this type directly.
//
// nonisolated because it's plain synchronous storage, not UI state - it shouldn't
// get pulled onto the main actor by the app's default actor isolation, otherwise
// deallocating it from background test code crashes.
nonisolated final class InMemoryBudgetStore: BudgetStore {
    private var budget: FoodBudget?
    private var spends: [GrocerySpend]
    private var wasteCosts: [WastedFoodCost]

    init(budget: FoodBudget? = nil,
         spends: [GrocerySpend] = [],
         wasteCosts: [WastedFoodCost] = []) {
        self.budget = budget
        self.spends = spends
        self.wasteCosts = wasteCosts
    }

    // MARK: Budget

    func activeBudget() -> FoodBudget? { budget }

    func saveBudget(_ budget: FoodBudget) {
        self.budget = budget
    }

    // MARK: Spends

    func allSpends() -> [GrocerySpend] { spends }

    func addSpend(_ spend: GrocerySpend) {
        spends.append(spend)
    }

    // MARK: Waste

    func allWasteCosts() -> [WastedFoodCost] { wasteCosts }

    func addWasteCost(_ cost: WastedFoodCost) {
        wasteCosts.append(cost)
    }

    func wasteAlreadyRecorded(for itemID: PantryItemID, on day: Date) -> Bool {
        let calendar = Calendar.current
        return wasteCosts.contains {
            $0.pantryItemID == itemID && calendar.isDate($0.discardedOn, inSameDayAs: day)
        }
    }
}
