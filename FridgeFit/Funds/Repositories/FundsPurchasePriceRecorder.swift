//
//  FundsPurchasePriceRecorder.swift
//  FridgeFit
//

import Foundation

// FridgeFunds' side of PurchasePriceRecording: the receipt scanner says "this
// pantry item cost $8.50", we store it as a per-unit cost so it shows up in
// Money in my fridge straight away.
final class FundsPurchasePriceRecorder: PurchasePriceRecording {
    private let environment: FundsEnvironment

    init(environment: FundsEnvironment) {
        self.environment = environment
    }

    func recordPurchasePrice(_ total: Decimal, for item: PantryItem) {
        // can't work out a per-unit cost from nothing
        guard item.quantity > 0 else { return }

        let currency = environment.budgetStore.activeBudget()?.currency ?? .aud
        let id = FridgeFitPantryReading.id(for: item)
        // keep an expiry date if one was already set for this item
        let existingExpiry = environment.priceStore.info(for: id)?.expiryDate

        let unitCost = Money(total / Decimal(item.quantity), currency)
        environment.priceStore.save(ItemPriceInfo(
            pantryItemID: id,
            unitCost: unitCost,
            expiryDate: existingExpiry
        ))
        environment.rememberPrice(of: item.name, unit: item.unit.rawValue, unitCost: unitCost)
    }
}
