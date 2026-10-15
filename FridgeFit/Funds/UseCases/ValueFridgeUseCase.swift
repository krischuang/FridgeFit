import Foundation

/// Adds up how much money is sitting in the fridge, and how much of it is about to
/// be wasted. Only items with a recorded cost count towards the dollar totals —
/// unpriced ones are tallied separately instead of just being ignored.
struct ValueFridgeUseCase {
    let pantry: PantryReading

    /// Items expiring within this many days (inclusive) count as at risk.
    static let atRiskWindowDays = 3

    /// Computes the current fridge valuation.
    /// - Parameters:
    ///   - now: the reference "today" (injectable for testing).
    ///   - currency: the currency to total in — normally the active budget's currency.
    func execute(now: Date = Date(), currency: Currency) -> FridgeValuation {
        let items = pantry.allItems()
        let valuedItems = items.filter { $0.unitCost != nil }
        let unvaluedCount = items.count - valuedItems.count

        let totalValue = valuedItems.reduce(Money.zero(in: currency)) { total, item in
            total + (item.lineValue ?? Money.zero(in: currency))
        }

        let atRiskItems = valuedItems.filter { item in
            guard let days = item.daysUntilExpiry(from: now) else { return false }
            return days <= Self.atRiskWindowDays
        }
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
            unvaluedItemCount: unvaluedCount
        )
    }
}
