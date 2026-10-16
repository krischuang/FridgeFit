//
//  InMemoryPantryReading.swift
//  FridgeFit
//

import Foundation

// in-memory PantryReading for the assignment - stands in for the Smart Fridge
// module's real inventory store. at group integration the shared inventory store
// replaces this with no change to any use case or view.
//
// nonisolated for the same reason as InMemoryBudgetStore - plain storage, shouldn't
// be forced onto the main actor.
nonisolated final class InMemoryPantryReading: PantryReading {
    private var items: [PantryItemSnapshot]

    init(items: [PantryItemSnapshot] = []) {
        self.items = items
    }

    func allItems() -> [PantryItemSnapshot] { items }

    func item(withID id: PantryItemID) -> PantryItemSnapshot? {
        items.first { $0.id == id }
    }

    // sample fridge so the app isn't empty on first launch - mix of soon-to-expire,
    // long-life, and unpriced items
    static func sample(currency: Currency, now: Date = Date()) -> InMemoryPantryReading {
        let calendar = Calendar.current
        func date(_ daysFromNow: Int) -> Date {
            calendar.date(byAdding: .day, value: daysFromNow, to: now) ?? now
        }

        let items: [PantryItemSnapshot] = [
            PantryItemSnapshot(id: PantryItemID("milk"), name: "Milk", quantity: 1,
                                unit: "L", expiryDate: date(2),
                                unitCost: Money(4.50, currency)),
            PantryItemSnapshot(id: PantryItemID("spinach"), name: "Baby Spinach", quantity: 1,
                                unit: "bag", expiryDate: date(1),
                                unitCost: Money(3.20, currency)),
            PantryItemSnapshot(id: PantryItemID("chicken"), name: "Chicken Breast", quantity: 0.6,
                                unit: "kg", expiryDate: date(3),
                                unitCost: Money(9.00, currency)),
            PantryItemSnapshot(id: PantryItemID("eggs"), name: "Eggs", quantity: 6,
                                unit: "each", expiryDate: date(12),
                                unitCost: Money(0.45, currency)),
            PantryItemSnapshot(id: PantryItemID("rice"), name: "Rice", quantity: 2,
                                unit: "kg", expiryDate: date(180),
                                unitCost: Money(3.00, currency)),
            PantryItemSnapshot(id: PantryItemID("leftoverSauce"), name: "Leftover Pasta Sauce",
                                quantity: 1, unit: "jar", expiryDate: date(4),
                                unitCost: nil)
        ]
        return InMemoryPantryReading(items: items)
    }
}
