//
//  InventoryEvent.swift
//  FridgeFit
//

import Foundation

/// What the household actually did with some food.
///
/// These are kept distinct because they mean different things when read back
/// as history: using food is not the same as correcting a typo in its
/// quantity, and throwing food away is not the same as finishing it.
nonisolated enum InventoryEventKind: String, Codable, Sendable {
    case added
    case used
    case quantityAdjusted
    case opened
    case finished
    case discarded
    case deleted
    case edited

    /// One line describing the event, for the activity list.
    var title: String {
        switch self {
        case .added: return "Added"
        case .used: return "Used"
        case .quantityAdjusted: return "Quantity corrected"
        case .opened: return "Opened"
        case .finished: return "Finished"
        case .discarded: return "Discarded"
        case .deleted: return "Record deleted"
        case .edited: return "Details updated"
        }
    }

    var symbolName: String {
        switch self {
        case .added: return "plus.circle.fill"
        case .used: return "minus.circle.fill"
        case .quantityAdjusted: return "slider.horizontal.3"
        case .opened: return "seal.fill"
        case .finished: return "checkmark.circle.fill"
        case .discarded: return "trash.fill"
        case .deleted: return "xmark.circle.fill"
        case .edited: return "pencil.circle.fill"
        }
    }
}

/// One committed change to the kitchen, kept so the user can see what
/// happened to their food.
///
/// Only *saved* operations create an event. Typing in the editor and
/// tapping around the UI do not - otherwise the history fills with
/// keystrokes and stops being readable.
///
/// ## Why finished and discarded items are not kept in the pantry
///
/// The branch this came from kept finished and discarded food in inventory
/// with a `status` field and filtered it out of the active list. That is not
/// done here: `EvaluateRecipeFeasibilityUseCase`,
/// `GetIngredientSubstitutionsUseCase` and `SuggestRecipesFromPantryUseCase`
/// all read `PantryRepository.fetchAll()` and have no notion of a status, so
/// a discarded item left in the collection would be counted as food the user
/// still has. Instead the pantry item is removed and the outcome is recorded
/// here - history lives in events, and the pantry keeps meaning exactly what
/// it already meant.
nonisolated struct InventoryEvent: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    /// The `PantryItem.id` this happened to. Kept even after the item is
    /// removed, so an item's history survives finishing or discarding it.
    let pantryItemID: UUID
    /// Denormalised on purpose: the item may be gone by the time this is
    /// read, and "Finished" with no name is not history.
    let itemName: String
    let kind: InventoryEventKind
    /// What changed, in the user's terms - "Used 200 g", "½ bottle".
    let note: String?
    let date: Date

    init(
        id: UUID = UUID(),
        pantryItemID: UUID,
        itemName: String,
        kind: InventoryEventKind,
        note: String? = nil,
        date: Date = .now
    ) {
        self.id = id
        self.pantryItemID = pantryItemID
        self.itemName = itemName
        self.kind = kind
        self.note = note
        self.date = date
    }
}
