//
//  UpdateInventoryItemDetailsUseCase.swift
//  FridgeFit
//

import Foundation

/// Everything the kitchen editor can change about an existing item.
nonisolated struct UpdateInventoryItemDetailsRequest: Equatable, Sendable {
    var itemID: UUID
    var name: String
    var category: IngredientCategory
    var storageLocation: StorageLocation
    var quantity: Quantity
    var expiryDate: Date?
    var openedState: OpenedState
    var lowStockThreshold: Double?
    /// Whether the user corrected the amount, as opposed to editing other
    /// details. Drives `quantityAdjusted` instead of `edited`, which is what
    /// keeps "I fixed a typo" out of the record as "I ate this".
    var quantityWasCorrected: Bool

    init(
        itemID: UUID,
        name: String,
        category: IngredientCategory,
        storageLocation: StorageLocation,
        quantity: Quantity,
        expiryDate: Date?,
        openedState: OpenedState,
        lowStockThreshold: Double?,
        quantityWasCorrected: Bool = false
    ) {
        self.itemID = itemID
        self.name = name
        self.category = category
        self.storageLocation = storageLocation
        self.quantity = quantity
        self.expiryDate = expiryDate
        self.openedState = openedState
        self.lowStockThreshold = lowStockThreshold
        self.quantityWasCorrected = quantityWasCorrected
    }
}

/// Why a detail edit was refused.
nonisolated enum UpdateInventoryItemDetailsError: LocalizedError, Equatable {
    case itemNotFound
    case missingIngredientName
    case invalidQuantity

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "That ingredient is no longer in your kitchen. Pull to refresh and try again."
        case .missingIngredientName:
            return "Give this food a name before saving it to your kitchen."
        case .invalidQuantity:
            return "Enter an amount of zero or more before saving this food."
        }
    }
}

/// Updates the details of an item already in the kitchen.
///
/// **Rules:** the name cannot become blank, the amount cannot go negative,
/// and the event written reflects what actually changed - a corrected amount
/// is `quantityAdjusted`, first opening a package is `opened`, anything else
/// is `edited`.
///
/// Zero *is* allowed here, unlike adding: running out of something you still
/// want to track is a real state, and the pantry has always permitted it
/// (see `AddPantryItemUseCase`'s `quantity >= 0`).
nonisolated struct UpdateInventoryItemDetailsUseCase {
    private let pantryRepository: PantryRepository
    private let eventRepository: InventoryEventRepository

    init(pantryRepository: PantryRepository, eventRepository: InventoryEventRepository) {
        self.pantryRepository = pantryRepository
        self.eventRepository = eventRepository
    }

    @discardableResult
    func execute(_ request: UpdateInventoryItemDetailsRequest) async throws -> (item: PantryItem, event: InventoryEvent) {
        guard let existing = try await pantryRepository.fetchAll().first(where: { $0.id == request.itemID }) else {
            throw UpdateInventoryItemDetailsError.itemNotFound
        }
        let resolved = try Self.apply(request, to: existing)

        try await pantryRepository.update(resolved.item)

        let event = InventoryEvent(
            pantryItemID: resolved.item.id,
            itemName: resolved.item.name,
            kind: resolved.kind,
            note: resolved.item.inventoryQuantity.displayText
        )
        try await eventRepository.append(event)
        return (resolved.item, event)
    }

    /// The pure part: validate, apply, and decide which event this is.
    static func apply(
        _ request: UpdateInventoryItemDetailsRequest,
        to existing: PantryItem
    ) throws -> (item: PantryItem, kind: InventoryEventKind) {
        let trimmedName = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw UpdateInventoryItemDetailsError.missingIngredientName
        }
        guard request.quantity.normalizedAmount >= 0 else {
            throw UpdateInventoryItemDetailsError.invalidQuantity
        }

        var item = existing
        let previousOpenedState = existing.opened
        item.ingredient.name = trimmedName
        item.ingredient.category = request.category
        item.storageLocation = request.storageLocation
        item.setInventoryQuantity(request.quantity)
        item.expiryDate = request.expiryDate
        item.openedState = request.openedState
        item.lowStockThreshold = request.lowStockThreshold

        let kind: InventoryEventKind
        if request.quantityWasCorrected {
            kind = .quantityAdjusted
        } else if previousOpenedState == .unopened, request.openedState == .opened {
            kind = .opened
        } else {
            kind = .edited
        }
        return (item, kind)
    }
}
