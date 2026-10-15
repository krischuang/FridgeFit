import Foundation

// read-only window onto the inventory that the Smart Fridge module (Module 1) owns.
// this module values food and flags what's at risk, but never writes pantry data -
// depending on a protocol instead of a concrete store means the real shared inventory
// store can replace this at group integration without touching any use case.
protocol PantryReading {
    func allItems() -> [PantryItemSnapshot]
    func item(withID id: PantryItemID) -> PantryItemSnapshot?
}

extension PantryReading {
    // items expiring within `days` days (already-expired ones included), soonest first
    func itemsExpiring(within days: Int, from reference: Date = Date()) -> [PantryItemSnapshot] {
        allItems()
            .compactMap { item -> (PantryItemSnapshot, Int)? in
                guard let d = item.daysUntilExpiry(from: reference) else { return nil }
                return d <= days ? (item, d) : nil
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }
}
