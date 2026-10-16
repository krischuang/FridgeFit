//
//  RecordIngredientUseUseCase.swift
//  FridgeFit
//

import Foundation

/// Why recording a use was refused. Messages are written for the user.
nonisolated enum RecordIngredientUseError: LocalizedError, Equatable {
    case itemNotFound
    case invalidUsedAmount
    case amountExceedsAvailable(available: Double, unit: String)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "That ingredient is no longer in your kitchen. Pull to refresh and try again."
        case .invalidUsedAmount:
            return "Enter an amount greater than zero before updating this food."
        case .amountExceedsAvailable(let available, let unit):
            return "Only \(QuantityFormatter.number(available)) \(unit) is available. Enter an amount up to \(QuantityFormatter.number(available)) \(unit)."
        }
    }
}

/// Records the user having used some of an ingredient, and reduces what is
/// left.
///
/// **Rules:** the amount must be greater than zero, it cannot exceed what is
/// there, the remainder can never go negative, and exactly one `used` event
/// is written per successful call.
///
/// The arithmetic lives on `Quantity`, not here - this use case's job is to
/// fetch, apply, persist and record, in that order, so a failure to save
/// never leaves a `used` event claiming something that didn't happen.
nonisolated struct RecordIngredientUseUseCase {
    private let pantryRepository: PantryRepository
    private let eventRepository: InventoryEventRepository

    init(pantryRepository: PantryRepository, eventRepository: InventoryEventRepository) {
        self.pantryRepository = pantryRepository
        self.eventRepository = eventRepository
    }

    /// - Returns: the item as it now stands, and the event that was written
    ///   (so the caller can undo it).
    @discardableResult
    func execute(itemID: UUID, usedAmount: Double) async throws -> (item: PantryItem, event: InventoryEvent) {
        guard let existing = try await pantryRepository.fetchAll().first(where: { $0.id == itemID }) else {
            throw RecordIngredientUseError.itemNotFound
        }
        let updated = try Self.apply(usedAmount: usedAmount, to: existing)

        try await pantryRepository.update(updated)

        let event = InventoryEvent(
            pantryItemID: updated.id,
            itemName: updated.name,
            kind: .used,
            note: "Used \(QuantityFormatter.number(usedAmount)) \(existing.unit.symbol)"
        )
        try await eventRepository.append(event)
        return (updated, event)
    }

    /// The pure part: validate the amount and subtract it.
    ///
    /// Static and separate so the rules can be tested without any storage,
    /// and so the view can validate what the user typed before committing.
    static func apply(usedAmount: Double, to item: PantryItem) throws -> PantryItem {
        guard usedAmount > 0 else {
            throw RecordIngredientUseError.invalidUsedAmount
        }
        var updated = item
        do {
            updated.setInventoryQuantity(try item.inventoryQuantity.subtracting(usedAmount))
        } catch IngredientQuantityError.amountExceedsAvailable(let available, let unit) {
            throw RecordIngredientUseError.amountExceedsAvailable(available: available, unit: unit)
        } catch {
            throw RecordIngredientUseError.invalidUsedAmount
        }
        return updated
    }
}
