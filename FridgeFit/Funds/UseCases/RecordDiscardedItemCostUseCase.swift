//
//  RecordDiscardedItemCostUseCase.swift
//  FridgeFit
//

import Foundation

// Turns a wasted pantry item into a dollar amount, using the item's recorded cost
// — so "I threw out some spinach" becomes a number the user actually feels.
struct RecordDiscardedItemCostUseCase {
    let pantry: PantryReading
    let budgetStore: BudgetStore

    // Failures that stop a waste cost from being recorded.
    enum Failure: LocalizedError, Equatable {
        // The referenced item is not in the fridge.
        case itemNotInPantry
        // The discarded quantity was zero or negative.
        case quantityNotPositive
        // The discarded quantity is more than what is on hand.
        case quantityExceedsOnHand(available: Double, unit: String)
        // The item has no recorded price, so its waste cannot be valued.
        case itemHasNoRecordedCost(itemName: String)
        // This item was already recorded as wasted today.
        case wasteAlreadyRecorded(itemName: String)

        var errorDescription: String? {
            switch self {
            case .itemNotInPantry:
                return "That item is no longer in your fridge, so it can't be logged as waste."
            case .quantityNotPositive:
                return "Enter how much you threw out — it needs to be more than zero."
            case .quantityExceedsOnHand(let available, let unit):
                return "You only have \(Self.trim(available)) \(unit) of this item. Enter that amount or less."
            case .itemHasNoRecordedCost(let itemName):
                return "\(itemName) has no recorded price, so we can't value the waste. Add its cost first."
            case .wasteAlreadyRecorded(let itemName):
                return "\(itemName) is already logged as wasted today — it won't be counted twice."
            }
        }

        // don't show "3.0" for a whole number
        private static func trim(_ value: Double) -> String {
            value == value.rounded() ? String(Int(value)) : String(value)
        }
    }

    // What happened to a recorded waste cost.
    nonisolated struct Recorded: Equatable {
        let cost: WastedFoodCost
        let outcome: FundsWriteOutcome
    }

    // Values and records a food-waste event.
    // - Returns: the ``WastedFoodCost`` and the write's real outcome.
    // - Throws: ``Failure`` when the waste is invalid, or the store's own
    //   error when it could not be written.
    @discardableResult
    func execute(itemID: PantryItemID,
                 quantityDiscarded: Double,
                 reason: DiscardReason,
                 discardedOn: Date = Date()) async throws -> Recorded {
        guard let item = pantry.item(withID: itemID) else {
            throw Failure.itemNotInPantry
        }
        guard quantityDiscarded > 0 else { throw Failure.quantityNotPositive }
        guard quantityDiscarded <= item.quantity else {
            throw Failure.quantityExceedsOnHand(available: item.quantity, unit: item.unit)
        }
        guard let unitCost = item.unitCost else {
            throw Failure.itemHasNoRecordedCost(itemName: item.name)
        }
        if budgetStore.wasteAlreadyRecorded(for: itemID, on: discardedOn) {
            throw Failure.wasteAlreadyRecorded(itemName: item.name)
        }

        let lostAmount = unitCost.scaled(by: Decimal(quantityDiscarded))
        let cost = WastedFoodCost(pantryItemID: itemID,
                                  quantityDiscarded: quantityDiscarded,
                                  lostAmount: lostAmount,
                                  discardedOn: discardedOn,
                                  reason: reason)
        let outcome = try await budgetStore.addWasteCost(cost)
        return Recorded(cost: cost, outcome: outcome)
    }
}
