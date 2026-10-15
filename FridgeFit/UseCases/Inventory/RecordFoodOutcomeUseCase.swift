//
//  RecordFoodOutcomeUseCase.swift
//  FridgeFit
//

import Foundation

/// Why food left the kitchen.
///
/// Finished means it was eaten; discarded means it was thrown out. Deleting
/// a record is deliberately *not* one of these - that corrects a mistake in
/// the data and says nothing about the food, so it is `.deleted` and is
/// never counted as waste.
nonisolated enum FoodOutcome: String, Codable, Equatable, Sendable {
    case finished
    case discarded

    var eventKind: InventoryEventKind {
        switch self {
        case .finished: return .finished
        case .discarded: return .discarded
        }
    }

    var pastTense: String {
        switch self {
        case .finished: return "finished"
        case .discarded: return "discarded"
        }
    }
}

nonisolated enum RecordFoodOutcomeError: LocalizedError, Equatable {
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "That ingredient is no longer in your kitchen. Pull to refresh and try again."
        }
    }
}

/// Records food leaving the kitchen, and takes it out of the pantry.
///
/// ## Why the item is removed rather than flagged
///
/// The branch this came from kept finished and discarded items in inventory
/// behind a `status` field. Doing that here would break three existing
/// features: `EvaluateRecipeFeasibilityUseCase`,
/// `SuggestRecipesFromPantryUseCase` and
/// `GetIngredientSubstitutionsUseCase` all read
/// `PantryRepository.fetchAll()` and have no concept of status, so food the
/// user threw away would still count towards "you can cook this".
///
/// So the pantry keeps meaning "what you have", removal goes through
/// `RemovePantryItemUseCase` like every other deletion, and the fact that it
/// was finished rather than discarded is preserved in the activity log. The
/// event carries the item's name and amount, which is what makes the removal
/// undoable - see `InventoryStore.undoLastAction()`.
nonisolated struct RecordFoodOutcomeUseCase {
    private let pantryRepository: PantryRepository
    private let removePantryItemUseCase: RemovePantryItemUseCase
    private let eventRepository: InventoryEventRepository

    init(pantryRepository: PantryRepository, eventRepository: InventoryEventRepository) {
        self.pantryRepository = pantryRepository
        self.removePantryItemUseCase = RemovePantryItemUseCase(pantryRepository: pantryRepository)
        self.eventRepository = eventRepository
    }

    /// - Returns: the item as it was before removal (so it can be restored)
    ///   and the event recorded.
    @discardableResult
    func execute(itemID: UUID, outcome: FoodOutcome) async throws -> (removed: PantryItem, event: InventoryEvent) {
        guard let item = try await pantryRepository.fetchAll().first(where: { $0.id == itemID }) else {
            throw RecordFoodOutcomeError.itemNotFound
        }

        try await removePantryItemUseCase.execute(id: itemID)

        let event = InventoryEvent(
            pantryItemID: item.id,
            itemName: item.name,
            kind: outcome.eventKind,
            note: item.inventoryQuantity.displayText
        )
        try await eventRepository.append(event)
        return (item, event)
    }

    /// Deletes a record without claiming anything about the food.
    ///
    /// Separate entry point rather than a third `FoodOutcome` case, because
    /// "this row was wrong" and "we ate it" must not end up in the same
    /// bucket when the history is read back.
    @discardableResult
    func deleteRecord(itemID: UUID) async throws -> (removed: PantryItem, event: InventoryEvent) {
        guard let item = try await pantryRepository.fetchAll().first(where: { $0.id == itemID }) else {
            throw RecordFoodOutcomeError.itemNotFound
        }

        try await removePantryItemUseCase.execute(id: itemID)

        let event = InventoryEvent(
            pantryItemID: item.id,
            itemName: item.name,
            kind: .deleted,
            note: item.inventoryQuantity.displayText
        )
        try await eventRepository.append(event)
        return (item, event)
    }
}
