//
//  ItemPriceStore.swift
//  FridgeFit
//

import Foundation

// where the price + expiry we attach to pantry items lives. same idea as BudgetStore:
// sync reads from a loaded snapshot, async writes that report what actually happened.
protocol ItemPriceStore: AnyObject {
    func info(for itemID: PantryItemID) -> ItemPriceInfo?
    @discardableResult
    func save(_ info: ItemPriceInfo) async throws -> FundsWriteOutcome
}

nonisolated final class InMemoryItemPriceStore: ItemPriceStore {
    private var byID: [PantryItemID: ItemPriceInfo]

    init(_ infos: [ItemPriceInfo] = []) {
        byID = Dictionary(infos.map { ($0.pantryItemID, $0) }, uniquingKeysWith: { _, last in last })
    }

    func info(for itemID: PantryItemID) -> ItemPriceInfo? { byID[itemID] }

    @discardableResult
    func save(_ info: ItemPriceInfo) async throws -> FundsWriteOutcome {
        byID[info.pantryItemID] = info
        // Nowhere else for it to go, so it is as committed as it will ever be.
        return .committed
    }
}
