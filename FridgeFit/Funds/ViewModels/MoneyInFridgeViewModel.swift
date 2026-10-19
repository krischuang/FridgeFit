//
//  MoneyInFridgeViewModel.swift
//  FridgeFit
//

import Foundation
import Observation

// drives "Money in My Fridge" - each item's dollar value, soonest-to-expire first
// so the most at-risk money is on top. also handles marking an item as wasted.
@Observable
final class MoneyInFridgeViewModel {
    private let environment: FundsEnvironment

    var items: [PantryItemSnapshot] = []
    var valuation: FridgeValuation?
    var actionMessage: String?
    var actionWasError = false

    init(environment: FundsEnvironment) {
        self.environment = environment
    }

    var currency: Currency { environment.budgetStore.activeBudget()?.currency ?? .aud }

    // items already logged as wasted today, so the UI can show a badge instead of
    // offering the action again
    var wastedTodayIDs: Set<PantryItemID> {
        let calendar = Calendar.current
        return Set(environment.budgetStore.allWasteCosts()
            .filter { calendar.isDateInToday($0.discardedOn) }
            .map(\.pantryItemID))
    }

    // loads fresh data from the stores first (Firestore in the real app), then recomputes
    func reload() async {
        await environment.reload()
        refresh()
    }

    func refresh(now: Date = Date()) {
        items = environment.pantry.allItems().sorted { lhs, rhs in
            let l = lhs.daysUntilExpiry(from: now) ?? Int.max
            let r = rhs.daysUntilExpiry(from: now) ?? Int.max
            return l < r
        }
        valuation = environment.valueFridge.execute(now: now, currency: currency)
    }

    func markWasted(_ item: PantryItemSnapshot, now: Date = Date()) {
        actionMessage = nil
        actionWasError = false
        do {
            let cost = try environment.recordDiscardedCost.execute(
                itemID: item.id,
                quantityDiscarded: item.quantity,
                reason: .expired,
                discardedOn: now
            )
            actionMessage = "Logged \(cost.lostAmount.formatted()) of \(item.name) as wasted."
        } catch {
            actionMessage = error.localizedDescription
            actionWasError = true
        }
        refresh(now: now)
    }

    func priceInfo(for item: PantryItemSnapshot) -> ItemPriceInfo? {
        environment.priceStore.info(for: item.id)
    }

    // people know what they paid for the whole pack, not the price per gram, so the
    // form asks for the total and we work out the per-unit cost from the quantity
    // on hand. returns an error message, or nil if it saved.
    func savePrice(for item: PantryItemSnapshot, totalPaidText: String) -> String? {
        let trimmed = totalPaidText.trimmingCharacters(in: .whitespaces)
        var unitCost: Money?
        if !trimmed.isEmpty {
            guard let total = Decimal(string: trimmed), total >= 0 else {
                return "Enter what you paid as a number, e.g. 4.50."
            }
            guard item.quantity > 0 else {
                return "This item has a quantity of 0 in your pantry - update the quantity first."
            }
            unitCost = Money(total / Decimal(item.quantity), currency)
        }
        // expiry lives on the pantry item now, just keep whatever old value we had
        let oldExpiry = environment.priceStore.info(for: item.id)?.expiryDate
        environment.priceStore.save(ItemPriceInfo(pantryItemID: item.id, unitCost: unitCost, expiryDate: oldExpiry))
        if let unitCost {
            environment.rememberPrice(of: item.name, unit: item.unit, unitCost: unitCost)
        }
        refresh()
        return nil
    }
}
