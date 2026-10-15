import Foundation

// where the price + expiry we attach to pantry items lives. same idea as BudgetStore:
// sync reads so the existing use cases don't change, storage hidden behind a protocol.
protocol ItemPriceStore: AnyObject {
    func info(for itemID: PantryItemID) -> ItemPriceInfo?
    func save(_ info: ItemPriceInfo)
}

nonisolated final class InMemoryItemPriceStore: ItemPriceStore {
    private var byID: [PantryItemID: ItemPriceInfo]

    init(_ infos: [ItemPriceInfo] = []) {
        byID = Dictionary(infos.map { ($0.pantryItemID, $0) }, uniquingKeysWith: { _, last in last })
    }

    func info(for itemID: PantryItemID) -> ItemPriceInfo? { byID[itemID] }

    func save(_ info: ItemPriceInfo) {
        byID[info.pantryItemID] = info
    }
}
