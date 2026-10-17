//
//  UpdatePantryItemUseCase.swift
//  FridgeFit
//

import Foundation

/// Updates an existing pantry item's quantity - the action
/// `AddPantryItemError.duplicateIngredient(name:)` points the user to when
/// they try to re-add something they already have.
///
/// Same quantity rule as `AddPantryItemUseCase` (can't go negative), but no
/// duplicate check here - updating in place is the whole point.
nonisolated struct UpdatePantryItemUseCase {
    private let pantryRepository: PantryRepository

    init(pantryRepository: PantryRepository) {
        self.pantryRepository = pantryRepository
    }

    @discardableResult
    func execute(id: UUID, quantity: Double, unit: MeasurementUnit) async throws -> PantryItem {
        guard quantity >= 0 else {
            throw AddPantryItemError.invalidQuantity
        }
        guard var item = try await pantryRepository.fetchAll().first(where: { $0.id == id }) else {
            throw UpdatePantryItemError.itemNotFound
        }
        item.quantity = quantity
        item.unit = unit
        try await pantryRepository.update(item)
        return item
    }
}
