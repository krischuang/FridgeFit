//
//  BudgetStore.swift
//  FridgeFit
//

import Foundation

// where the budget/spends/waste data actually lives is hidden behind this protocol -
// use cases only know about business logic, not storage. in-memory implementation for
// this assignment (InMemoryBudgetStore); swapping in SwiftData at group integration
// won't need any change to the use cases or views.
protocol BudgetStore: AnyObject {

    // MARK: Budget
    func activeBudget() -> FoodBudget?
    func saveBudget(_ budget: FoodBudget)

    // MARK: Spends
    func allSpends() -> [GrocerySpend]
    func addSpend(_ spend: GrocerySpend)

    // MARK: Waste
    func allWasteCosts() -> [WastedFoodCost]
    func addWasteCost(_ cost: WastedFoodCost)
    // true if this item was already logged as wasted that day - stops double counting
    func wasteAlreadyRecorded(for itemID: PantryItemID, on day: Date) -> Bool
}
