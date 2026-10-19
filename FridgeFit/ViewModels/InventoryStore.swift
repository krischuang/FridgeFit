//
//  InventoryStore.swift
//  FridgeFit
//

import Combine
import Foundation

/// A mutually exclusive snapshot of the pantry's expiry states.
///
/// Expiry is resolved through `ExpiryService`, so Home uses the same
/// calendar-day and timezone semantics as My Fridge. Undated and non-urgent
/// items are fresh; expired items are never included in that cooking-safe
/// count.
nonisolated struct InventoryExpirySummary: Equatable {
    let freshItems: [PantryItem]
    let expiringItems: [PantryItem]
    let expiredItems: [PantryItem]

    init(items: [PantryItem], now: Date = .now, calendar: Calendar = .current) {
        var fresh: [PantryItem] = []
        var expiring: [PantryItem] = []
        var expired: [PantryItem] = []

        for item in items {
            guard let state = ExpiryService.state(for: item.expiryDate, now: now, calendar: calendar) else {
                fresh.append(item)
                continue
            }

            if state.urgency == .expired {
                expired.append(item)
            } else if state.shouldPrioritise {
                expiring.append(item)
            } else {
                fresh.append(item)
            }
        }

        freshItems = fresh
        expiringItems = expiring
        expiredItems = expired
    }
}

/// The kitchen screen's view of the pantry.
///
/// ## What this replaces
///
/// The branch this UI came from had an `InventoryService` that owned an
/// array of items and wrote them to a JSON file in Application Support.
/// That is gone: this holds no storage of its own, writes nothing to disk,
/// and every mutation goes through the same `PantryRepository` the Pantry
/// tab, the receipt scanner and the camera review sheet already use. So the
/// kitchen is per-user, scoped by Firebase auth, synced across devices, and
/// subject to the same Firestore rules - none of which a local JSON file
/// could offer.
///
/// ## Why it is `ObservableObject` and not `@Observable`
///
/// Every other view model in FridgeFit is `ObservableObject` with
/// `@Published`. Keeping one idiom means a sheet can be handed this store
/// the same way `PantryView` is handed `PantryViewModel`, with no mixed
/// lifetime rules for the next person to reason about.
///
/// ## Reload-after-write
///
/// Each mutation re-reads the pantry rather than patching the local array.
/// It costs a round trip, but the same pantry is being written by the
/// receipt scanner and the camera on another device, and a local patch would
/// quietly diverge from what is actually stored. `PantryViewModel` already
/// works this way; this matches it.
@MainActor
final class InventoryStore: ObservableObject {
    /// What the user currently has, expiry-soonest first.
    @Published private(set) var items: [PantryItem] = []
    /// Recent activity, newest first.
    @Published private(set) var events: [InventoryEvent] = []
    @Published private(set) var isLoading = false
    /// A failure the whole screen needs to report - usually not signed in,
    /// or offline.
    @Published var errorMessage: String?
    /// The last thing that happened, for the undo bar: "Milk finished".
    @Published private(set) var lastMessage: String?

    /// How many events the activity sheet reads. A kitchen generates a few
    /// events a day, so this is months of history without an unbounded read
    /// on a collection that only ever grows.
    static let activityFetchLimit = 200

    private let pantryRepository: PantryRepository
    private let eventRepository: InventoryEventRepository
    private let addInventoryItemUseCase: AddInventoryItemUseCase
    private let updateDetailsUseCase: UpdateInventoryItemDetailsUseCase
    private let recordUseUseCase: RecordIngredientUseUseCase
    private let recordOutcomeUseCase: RecordFoodOutcomeUseCase
    private let identifyExpiring: IdentifyExpiringInventoryUseCase

    /// What the last action changed, so it can be put back.
    ///
    /// Holds the item as it was *before* the action plus the events the
    /// action wrote. Undo restores the item and deletes those events, so
    /// history doesn't keep claiming something the user took back.
    private var undo: UndoState?

    private struct UndoState {
        /// `nil` when the action created the item - undoing an add means
        /// removing it, not restoring an earlier version.
        let previousItem: PantryItem?
        let createdItemID: UUID?
        let eventIDs: [UUID]
        let message: String
    }

    /// Both repositories are required rather than defaulted.
    ///
    /// A default would have to be an in-memory store, and silently writing a
    /// user's food into a dictionary that disappears is a worse failure than
    /// a compile error - the same reasoning as the deliberately *real*
    /// default on `PantryRepositoryKey`. (It also avoids constructing a
    /// main-actor type in a default-argument expression, which this project's
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting warns about.)
    init(
        pantryRepository: PantryRepository,
        eventRepository: InventoryEventRepository,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        self.pantryRepository = pantryRepository
        self.eventRepository = eventRepository
        self.addInventoryItemUseCase = AddInventoryItemUseCase(
            pantryRepository: pantryRepository,
            eventRepository: eventRepository
        )
        self.updateDetailsUseCase = UpdateInventoryItemDetailsUseCase(
            pantryRepository: pantryRepository,
            eventRepository: eventRepository
        )
        self.recordUseUseCase = RecordIngredientUseUseCase(
            pantryRepository: pantryRepository,
            eventRepository: eventRepository
        )
        self.recordOutcomeUseCase = RecordFoodOutcomeUseCase(
            pantryRepository: pantryRepository,
            eventRepository: eventRepository
        )
        self.identifyExpiring = IdentifyExpiringInventoryUseCase(now: now, calendar: calendar)
    }

    var canUndoLastAction: Bool { undo != nil }

    // MARK: - Reading

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await pantryRepository.fetchAll()
            // Expiry-soonest first, undated last, ties alphabetical. The
            // kitchen screen splits this into "Use First" and the rest, but
            // both halves want the same order within themselves.
            items = fetched.sorted { lhs, rhs in
                let left = lhs.expiryState?.daysUntilExpiry ?? Int.max
                let right = rhs.expiryState?.daysUntilExpiry ?? Int.max
                if left != right { return left < right }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        do {
            events = try await eventRepository.fetchAll(limit: Self.activityFetchLimit)
        } catch {
            // The pantry loaded; only history didn't. Surfacing this as the
            // screen's error would imply the food list is wrong when it is
            // fine, so the activity sheet simply shows nothing.
            events = []
        }
    }

    func item(id: UUID) -> PantryItem? {
        items.first { $0.id == id }
    }

    func history(for itemID: UUID) -> [InventoryEvent] {
        events.filter { $0.pantryItemID == itemID }.sorted { $0.date > $1.date }
    }

    func useFirstItems(searchText: String = "", filter: InventoryFilter = .all) -> [PantryItem] {
        identifyExpiring.execute(items: items, searchText: searchText, filter: filter)
    }

    func remainingItems(searchText: String = "", filter: InventoryFilter = .all) -> [PantryItem] {
        identifyExpiring.remainder(items: items, searchText: searchText, filter: filter)
    }

    func expirySummary(now: Date = .now, calendar: Calendar = .current) -> InventoryExpirySummary {
        InventoryExpirySummary(items: items, now: now, calendar: calendar)
    }

    // MARK: - Writing

    func add(_ request: AddInventoryItemRequest) async throws {
        let result = try await addInventoryItemUseCase.execute(request)
        undo = UndoState(
            previousItem: nil,
            createdItemID: result.item.id,
            eventIDs: [result.event.id],
            message: "\(result.item.name) removed"
        )
        await finish(message: "\(result.item.name) added")
    }

    func updateDetails(_ request: UpdateInventoryItemDetailsRequest) async throws {
        let previous = item(id: request.itemID)
        let result = try await updateDetailsUseCase.execute(request)
        undo = UndoState(
            previousItem: previous,
            createdItemID: nil,
            eventIDs: [result.event.id],
            message: "\(result.item.name) restored"
        )
        await finish(message: "\(result.item.name) updated")
    }

    func recordUse(of itemID: UUID, amount: Double) async throws {
        let previous = item(id: itemID)
        let result = try await recordUseUseCase.execute(itemID: itemID, usedAmount: amount)
        undo = UndoState(
            previousItem: previous,
            createdItemID: nil,
            eventIDs: [result.event.id],
            message: "\(result.item.name) restored"
        )
        await finish(message: result.event.note ?? "\(result.item.name) updated")
    }

    /// Nudges the amount up or down by `delta` without recording it as use.
    ///
    /// A negative delta goes through `recordUse` so the "can't use more than
    /// you have" rule applies and the activity says `used`. A positive one is
    /// a correction - you cannot "un-eat" food, so adding is always
    /// `quantityAdjusted`.
    func adjustQuantity(of itemID: UUID, by delta: Double) async throws {
        guard let existing = item(id: itemID) else {
            throw RecordIngredientUseError.itemNotFound
        }
        if delta < 0 {
            try await recordUse(of: itemID, amount: abs(delta))
        } else {
            try await updateDetails(UpdateInventoryItemDetailsRequest(
                itemID: itemID,
                name: existing.name,
                category: existing.ingredient.category,
                storageLocation: existing.storage,
                quantity: existing.inventoryQuantity.adjusted(by: delta),
                expiryDate: existing.expiryDate,
                openedState: existing.opened,
                lowStockThreshold: existing.lowStockThreshold,
                quantityWasCorrected: true
            ))
        }
    }

    /// Commits a drawer save: detail edits and a recorded use, as one
    /// undoable action.
    ///
    /// The two are separate writes - there is no transaction spanning a
    /// details update and a use - but they share a single undo entry holding
    /// the item as it was before either, so taking the whole save back
    /// restores one coherent state rather than half of it.
    func saveDrawerChanges(
        details: UpdateInventoryItemDetailsRequest,
        includeDetails: Bool,
        usedAmount: Double
    ) async throws {
        let previous = item(id: details.itemID)
        var eventIDs: [UUID] = []
        var message: String?

        if includeDetails {
            let result = try await updateDetailsUseCase.execute(details)
            eventIDs.append(result.event.id)
            message = "\(result.item.name) updated"
        }

        if usedAmount > 0 {
            let result = try await recordUseUseCase.execute(itemID: details.itemID, usedAmount: usedAmount)
            eventIDs.append(result.event.id)
            message = result.event.note ?? message
        }

        guard !eventIDs.isEmpty else { return }

        undo = UndoState(
            previousItem: previous,
            createdItemID: nil,
            eventIDs: eventIDs,
            message: "\(previous?.name ?? "Item") restored"
        )
        await finish(message: message)
    }

    func record(outcome: FoodOutcome, for itemID: UUID) async throws {
        let result = try await recordOutcomeUseCase.execute(itemID: itemID, outcome: outcome)
        undo = UndoState(
            previousItem: result.removed,
            createdItemID: nil,
            eventIDs: [result.event.id],
            message: "\(result.removed.name) restored"
        )
        await finish(message: "\(result.removed.name) \(outcome.pastTense)")
    }

    func deleteRecord(for itemID: UUID) async throws {
        let result = try await recordOutcomeUseCase.deleteRecord(itemID: itemID)
        undo = UndoState(
            previousItem: result.removed,
            createdItemID: nil,
            eventIDs: [result.event.id],
            message: "\(result.removed.name) restored"
        )
        await finish(message: "\(result.removed.name) deleted")
    }

    /// Puts back whatever the last action changed.
    ///
    /// Restoring a removed item re-adds it under its original id, so its
    /// history still points at the right thing. The events the undone action
    /// wrote are deleted rather than balanced with a compensating entry -
    /// an action the user took back did not happen, and the log should not
    /// imply it did.
    func undoLastAction() async {
        guard let undo else { return }
        self.undo = nil
        do {
            if let previousItem = undo.previousItem {
                if items.contains(where: { $0.id == previousItem.id }) {
                    try await pantryRepository.update(previousItem)
                } else {
                    try await pantryRepository.add(previousItem)
                }
            } else if let createdItemID = undo.createdItemID {
                try await pantryRepository.remove(id: createdItemID)
            }
            try await eventRepository.remove(ids: undo.eventIDs)
            await finish(message: undo.message)
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }

    /// Clears the undo bar, after the user dismisses it or acts again.
    func clearLastMessage() {
        lastMessage = nil
    }

    /// Reloads and reports. Every successful mutation ends here, so there is
    /// one place that decides what the screen shows afterwards.
    private func finish(message: String?) async {
        await load()
        lastMessage = message
    }
}
