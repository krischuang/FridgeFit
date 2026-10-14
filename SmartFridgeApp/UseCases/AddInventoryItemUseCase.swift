import Foundation

public enum AddInventoryItemError: LocalizedError, Equatable {
    case missingIngredientName
    case invalidQuantity

    public var errorDescription: String? {
        switch self {
        case .missingIngredientName:
            return "Give this food a name before adding it to your kitchen."
        case .invalidQuantity:
            return "Enter an amount greater than zero before adding this food."
        }
    }
}

public struct AddInventoryItemRequest: Sendable {
    public var name: String
    public var category: FoodCategory
    public var storageLocation: FoodStorageLocation
    public var quantity: IngredientQuantity
    public var expiryDate: Date?
    public var openState: FoodOpenState
    public var lowStockThreshold: Double?

    public init(
        name: String,
        category: FoodCategory,
        storageLocation: FoodStorageLocation,
        quantity: IngredientQuantity,
        expiryDate: Date? = nil,
        openState: FoodOpenState = .notApplicable,
        lowStockThreshold: Double? = nil
    ) {
        self.name = name
        self.category = category
        self.storageLocation = storageLocation
        self.quantity = quantity
        self.expiryDate = expiryDate
        self.openState = openState
        self.lowStockThreshold = lowStockThreshold
    }
}

/// Adds a new food item to active household inventory.
///
/// Business Rules:
/// - The food name must not be blank.
/// - Initial quantity must be greater than zero.
/// - Expiry tracking is optional.
/// - Successful additions create one meaningful `added` activity.
@MainActor
public struct AddInventoryItemUseCase {
    private let repository: any HouseholdInventoryRepository

    public init(repository: any HouseholdInventoryRepository) {
        self.repository = repository
    }

    @discardableResult
    public func execute(_ request: AddInventoryItemRequest) throws -> InventoryItem {
        let trimmedName = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw AddInventoryItemError.missingIngredientName
        }
        guard request.quantity.isPositive else {
            throw AddInventoryItemError.invalidQuantity
        }

        let item = InventoryItem(
            name: trimmedName,
            category: request.category,
            storageLocation: request.storageLocation,
            quantity: request.quantity,
            expiryDate: request.expiryDate,
            openedState: request.openState,
            lowStockThreshold: request.lowStockThreshold
        )
        try repository.saveInventoryItem(item, activity: .added, note: item.quantity.displayText, message: "\(item.name) added")
        return item
    }
}
