//
//  BudgetStore.swift
//  FridgeFit
//

import Foundation

// where the budget/spends/waste data actually lives is hidden behind this protocol -
// use cases only know about business logic, not storage. Three implementations:
// InMemoryBudgetStore (tests and previews), SwiftDataBudgetStore (the shipping
// on-device store) and FirestoreBudgetStore (Firebase mode).
//
// ## Reads are synchronous, writes are not
//
// The reads answer from a snapshot that `load()` filled, which is why they can stay
// sync and why the Impact screen can compute a whole summary without awaiting
// anything. The writes are `async throws` and report a `FundsWriteOutcome`, which
// they did not used to do: they returned `Void`, updated the local copy, and threw
// the real result away. A Firestore write refused for permissions would update the
// screen, log a line nobody reads, and leave the user looking at a budget the backend
// had rejected. See `FundsWriteOutcome` for why the success side needs two cases
// rather than one.
protocol BudgetStore: AnyObject {

    // MARK: Budget
    func activeBudget() -> FoodBudget?
    @discardableResult
    func saveBudget(_ budget: FoodBudget) async throws -> FundsWriteOutcome

    // MARK: Spends
    func allSpends() -> [GrocerySpend]
    @discardableResult
    func addSpend(_ spend: GrocerySpend) async throws -> FundsWriteOutcome

    // MARK: Waste
    func allWasteCosts() -> [WastedFoodCost]
    @discardableResult
    func addWasteCost(_ cost: WastedFoodCost) async throws -> FundsWriteOutcome
    // true if this item was already logged as wasted that day - stops double counting
    func wasteAlreadyRecorded(for itemID: PantryItemID, on day: Date) -> Bool
}
