//
//  AddInventoryItemUseCase.swift
//  FridgeFit
//

import Foundation

/// Everything the kitchen editor can say about a new item.
nonisolated struct AddInventoryItemRequest: Equatable, Sendable {
    var name: String
    var category: IngredientCategory
    var storageLocation: StorageLocation
    var quantity: Quantity
    var expiryDate: Date?
    var openedState: OpenedState
    var lowStockThreshold: Double?

    init(
        name: String,
        category: IngredientCategory,
        storageLocation: StorageLocation,
        quantity: Quantity,
        expiryDate: Date? = nil,
        openedState: OpenedState = .notApplicable,
        lowStockThreshold: Double? = nil
    ) {
        self.name = name
        self.category = category
        self.storageLocation = storageLocation
        self.quantity = quantity
        self.expiryDate = expiryDate
        self.openedState = openedState
        self.lowStockThreshold = lowStockThreshold
    }
}

/// Why adding from the kitchen screen was refused.
nonisolated enum AddInventoryItemError: LocalizedError, Equatable {
    case invalidQuantity

    var errorDescription: String? {
        switch self {
        case .invalidQuantity:
            return "Enter an amount greater than zero before adding this food."
        }
    }
}

/// Adds an item from the kitchen UI.
///
/// Deliberately thin, for the same reason `AddDetectedIngredientsUseCase` is:
/// name validation and the duplicate rule already exist in
/// `AddPantryItemUseCase` and are not reimplemented here. The kitchen screen
/// therefore gets the *same* behaviour as the Pantry tab - including being
/// told to update the existing entry rather than adding a second row for
/// food the user already has - because it is the same code path.
///
/// What this adds on top is the one rule the pantry doesn't have (a new item
/// must have a positive amount, where the pantry allows zero for something
/// you've run out of but still track) and the `added` activity event.
nonisolated struct AddInventoryItemUseCase {
    private let addPantryItemUseCase: AddPantryItemUseCase
    private let eventRepository: InventoryEventRepository

    init(addPantryItemUseCase: AddPantryItemUseCase, eventRepository: InventoryEventRepository) {
        self.addPantryItemUseCase = addPantryItemUseCase
        self.eventRepository = eventRepository
    }

    init(pantryRepository: PantryRepository, eventRepository: InventoryEventRepository) {
        self.init(
            addPantryItemUseCase: AddPantryItemUseCase(pantryRepository: pantryRepository),
            eventRepository: eventRepository
        )
    }

    /// - Throws: `AddInventoryItemError.invalidQuantity`, or anything
    ///   `AddPantryItemUseCase` throws - a blank name or a duplicate, with
    ///   its existing user-facing message.
    @discardableResult
    func execute(_ request: AddInventoryItemRequest) async throws -> (item: PantryItem, event: InventoryEvent) {
        guard request.quantity.isPositive else {
            throw AddInventoryItemError.invalidQuantity
        }

        let packageReading = request.quantity.packageReading
        let item = try await addPantryItemUseCase.execute(
            name: request.name,
            quantity: request.quantity.normalizedAmount,
            unit: request.quantity.storageUnit,
            category: request.category,
            expiryDate: request.expiryDate,
            storageLocation: request.storageLocation,
            openedState: request.openedState,
            lowStockThreshold: request.lowStockThreshold,
            packageUnit: packageReading?.unit,
            packageLevel: packageReading?.level
        )

        let event = InventoryEvent(
            pantryItemID: item.id,
            itemName: item.name,
            kind: .added,
            note: request.quantity.displayText
        )
        try await eventRepository.append(event)
        return (item, event)
    }
}

extension Quantity {
    /// The package kind and level, when this is a packaged quantity.
    ///
    /// Saves every caller writing the same `if case .package` to pull two
    /// values out for storage.
    var packageReading: (unit: PackageUnit, level: PackageLevel)? {
        if case .package(_, let unit, let level) = self {
            return (unit, level)
        }
        return nil
    }
}
