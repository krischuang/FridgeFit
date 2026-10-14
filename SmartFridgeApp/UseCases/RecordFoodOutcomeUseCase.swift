import Foundation

public enum RecordFoodOutcomeError: LocalizedError, Equatable {
    case itemNotFound

    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "This food is no longer in your kitchen. Refresh your kitchen and try again."
        }
    }
}

/// Records why food leaves active household inventory.
///
/// Business Rules:
/// - Finished and discarded are different physical food outcomes.
/// - Delete Record is not a food outcome.
/// - A committed outcome removes the item from active inventory and records
///   one matching activity.
@MainActor
public struct RecordFoodOutcomeUseCase {
    private let repository: any HouseholdInventoryRepository

    public init(repository: any HouseholdInventoryRepository) {
        self.repository = repository
    }

    public func execute(itemID: UUID, outcome: FoodOutcome) throws {
        guard let item = repository.inventoryItem(id: itemID), item.isActive else {
            throw RecordFoodOutcomeError.itemNotFound
        }
        try repository.removeFromActiveInventory(item, outcome: outcome)
    }

    public func execute(item: InventoryItem, outcome: FoodOutcome) throws {
        guard repository.inventoryItem(id: item.id)?.isActive == true else {
            throw RecordFoodOutcomeError.itemNotFound
        }
        try repository.removeFromActiveInventory(item, outcome: outcome)
    }
}
