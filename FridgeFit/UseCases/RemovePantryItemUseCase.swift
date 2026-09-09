//
//  RemovePantryItemUseCase.swift
//  FridgeFit
//

import Foundation

/// Removes an item the user has used up (or added by mistake).
///
/// Its own use case, not a direct repository call, so removal goes through
/// the same path as every other pantry mutation, and "item not found"
/// (removed elsewhere between the list rendering and the swipe landing) is
/// a real error instead of a silent no-op.
struct RemovePantryItemUseCase {
    private let pantryRepository: PantryRepository

    init(pantryRepository: PantryRepository) {
        self.pantryRepository = pantryRepository
    }

    @discardableResult
    func execute(id: UUID) async throws -> PantryItem {
        guard let item = try await pantryRepository.fetchAll().first(where: { $0.id == id }) else {
            throw RemovePantryItemError.pantryItemNotFound
        }
        try await pantryRepository.remove(id: id)
        return item
    }
}
