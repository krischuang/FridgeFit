import Foundation

public enum UpdateInventoryItemDetailsError: LocalizedError, Equatable {
    case itemNotFound
    case missingIngredientName
    case invalidQuantity

    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "This food is no longer in your kitchen. Refresh your kitchen and try again."
        case .missingIngredientName:
            return "Give this food a name before saving it to your kitchen."
        case .invalidQuantity:
            return "Enter an amount of zero or more before saving this food."
        }
    }
}

public struct UpdateInventoryItemDetailsRequest: Sendable {
    public var itemID: UUID
    public var name: String
    public var category: FoodCategory
    public var storageLocation: FoodStorageLocation
    public var quantity: IngredientQuantity
    public var expiryDate: Date?
    public var openState: FoodOpenState
    public var lowStockThreshold: Double?
    public var quantityWasCorrected: Bool

    public init(
        itemID: UUID,
        name: String,
        category: FoodCategory,
        storageLocation: FoodStorageLocation,
        quantity: IngredientQuantity,
        expiryDate: Date?,
        openState: FoodOpenState,
        lowStockThreshold: Double?,
        quantityWasCorrected: Bool = false
    ) {
        self.itemID = itemID
        self.name = name
        self.category = category
        self.storageLocation = storageLocation
        self.quantity = quantity
        self.expiryDate = expiryDate
        self.openState = openState
        self.lowStockThreshold = lowStockThreshold
        self.quantityWasCorrected = quantityWasCorrected
    }
}

public struct UpdateInventoryItemDetailsValidation: Sendable {
    public var item: InventoryItem
    public var activity: InventoryEventKind
}

/// Updates meaningful details of an existing household food item.
///
/// Business Rules:
/// - Name cannot become blank.
/// - Corrected quantity cannot be negative.
/// - Quantity corrections are recorded as `quantityAdjusted`, not `used`.
@MainActor
public struct UpdateInventoryItemDetailsUseCase {
    private let repository: any HouseholdInventoryRepository

    public init(repository: any HouseholdInventoryRepository) {
        self.repository = repository
    }

    @discardableResult
    public func execute(_ request: UpdateInventoryItemDetailsRequest) throws -> InventoryItem {
        let validation = try validate(request)
        try repository.saveInventoryItem(validation.item, activity: validation.activity, note: nil, message: "\(validation.item.name) updated")
        return validation.item
    }

    public func validate(_ request: UpdateInventoryItemDetailsRequest) throws -> UpdateInventoryItemDetailsValidation {
        guard var item = repository.inventoryItem(id: request.itemID), item.isActive else {
            throw UpdateInventoryItemDetailsError.itemNotFound
        }
        let trimmedName = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw UpdateInventoryItemDetailsError.missingIngredientName
        }
        guard request.quantity.normalizedAmount.map({ $0 >= 0 }) ?? true else {
            throw UpdateInventoryItemDetailsError.invalidQuantity
        }

        let previousOpenState = item.openedState
        item.name = trimmedName
        item.category = request.category
        item.storageLocation = request.storageLocation
        item.quantity = request.quantity
        item.expiryDate = request.expiryDate
        item.openedState = request.openState
        item.lowStockThreshold = request.lowStockThreshold

        let event: InventoryEventKind
        if request.quantityWasCorrected {
            event = .quantityAdjusted
        } else if previousOpenState == .unopened, item.openedState == .opened {
            event = .opened
        } else {
            event = .edited
        }

        return UpdateInventoryItemDetailsValidation(item: item, activity: event)
    }
}
