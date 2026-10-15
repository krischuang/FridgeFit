import Foundation
@testable import FridgeFit

// fixed dates so tests don't depend on what day they actually run. day(0) is the
// anchor itself, positive offsets move forward from there.
enum TestDates {
    static let anchor: Date = {
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 1
        components.hour = 12
        return Calendar.current.date(from: components)!
    }()

    static func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: anchor)!
    }
}

// shorthand for an AUD amount
func aud(_ amount: Decimal) -> Money {
    Money(amount, .aud)
}

// weekly budget starting at TestDates.anchor
func makeWeeklyBudget(limit: Decimal, currency: Currency = .aud) -> FoodBudget {
    FoodBudget(limit: Money(limit, currency), cadence: .weekly, startDate: TestDates.anchor)
}

// pantry with a single item, id "test-item", for RecordDiscardedItemCostUseCase tests
func makePantry(unitCost: Money?,
                 quantity: Double = 10,
                 unit: String = "each",
                 name: String = "Test Item") -> PantryReading {
    let item = PantryItemSnapshot(id: PantryItemID("test-item"),
                                  name: name,
                                  quantity: quantity,
                                  unit: unit,
                                  expiryDate: nil,
                                  unitCost: unitCost)
    return InMemoryPantryReading(items: [item])
}
