import Foundation

/// Why a pantry item left the fridge without being eaten.
enum DiscardReason: String, Codable, CaseIterable, Sendable {
    case expired
    case spoiled
    case discardedByUser

    var displayName: String {
        switch self {
        case .expired: return "Expired"
        case .spoiled: return "Spoiled"
        case .discardedByUser: return "Thrown out"
        }
    }
}

/// The money value of one wasted pantry item, derived from its recorded cost.
struct WastedFoodCost: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let pantryItemID: PantryItemID
    /// How much of the item, in its own unit, was discarded.
    let quantityDiscarded: Double
    /// The money value of what was discarded.
    let lostAmount: Money
    let discardedOn: Date
    let reason: DiscardReason

    init(id: UUID = UUID(),
         pantryItemID: PantryItemID,
         quantityDiscarded: Double,
         lostAmount: Money,
         discardedOn: Date = Date(),
         reason: DiscardReason) {
        self.id = id
        self.pantryItemID = pantryItemID
        self.quantityDiscarded = quantityDiscarded
        self.lostAmount = lostAmount
        self.discardedOn = discardedOn
        self.reason = reason
    }
}
