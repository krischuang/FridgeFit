//
//  ValueFridgeUseCase.swift
//  FridgeFit
//

import Foundation

// Adds up how much money is sitting in the fridge, and how much of it is about to
// be wasted. Only items with a recorded cost count towards the dollar totals —
// unpriced ones are tallied separately instead of just being ignored.
struct ValueFridgeUseCase {
    let pantry: PantryReading

    // Items expiring within this many days (inclusive) count as at risk.
    // Already-expired items are included: a negative day count is still
    // `<= 3`, and food that went off yesterday is the most urgent thing in
    // the fridge, not the least.
    static let atRiskWindowDays = 3

    // Computes the current fridge valuation.
    // - Parameters:
    //   - now: the reference "today" (injectable for testing).
    //   - currency: the currency to total in — normally the active budget's currency.
    func execute(now: Date = Date(), currency: Currency) -> FridgeValuation {
        let items = pantry.allItems()
        let valuedItems = items.filter { $0.unitCost != nil }
        let unvaluedCount = items.count - valuedItems.count

        let totalValue = valuedItems.reduce(Money.zero(in: currency)) { total, item in
            total + (item.lineValue ?? Money.zero(in: currency))
        }

        let atRiskAll = Self.atRiskItems(in: items, now: now)
        let atRiskItems = atRiskAll.filter { $0.unitCost != nil }
        let atRiskValue = atRiskItems.reduce(Money.zero(in: currency)) { total, item in
            total + (item.lineValue ?? Money.zero(in: currency))
        }

        // spread the at-risk value over days until the soonest of those items expires,
        // so it reads as "use up $X/day" instead of one scary lump sum
        let soonestExpiryDays = atRiskItems.compactMap { $0.daysUntilExpiry(from: now) }.min()
        let daysToSpread = max(soonestExpiryDays ?? 1, 1)
        let atRiskPerDay = atRiskValue.dividedEvenly(by: daysToSpread)

        return FridgeValuation(
            totalValue: totalValue,
            atRiskValue: atRiskValue,
            atRiskPerDay: atRiskPerDay,
            valuedItemCount: valuedItems.count,
            unvaluedItemCount: unvaluedCount,
            atRiskItemCount: atRiskItems.count,
            atRiskUnvaluedCount: atRiskAll.count - atRiskItems.count
        )
    }

    // Everything inside the at-risk window, priced or not, soonest first.
    //
    // The list the Impact screen renders and the totals above come from this
    // one function, so a row can never appear in the list without being
    // counted - or be counted without appearing.
    func atRiskItems(now: Date = Date()) -> [PantryItemSnapshot] {
        Self.atRiskItems(in: pantry.allItems(), now: now)
    }

    private static func atRiskItems(in items: [PantryItemSnapshot], now: Date) -> [PantryItemSnapshot] {
        items
            .compactMap { item -> (PantryItemSnapshot, Int)? in
                guard let days = item.daysUntilExpiry(from: now) else { return nil }
                return days <= atRiskWindowDays ? (item, days) : nil
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
            }
            .map(\.0)
    }
}
