import Foundation
import Observation

public struct IngredientConsumption: Sendable {
    public var ingredientID: UUID
    public var amount: Double

    public init(ingredientID: UUID, amount: Double) {
        self.ingredientID = ingredientID
        self.amount = amount
    }
}

public enum InventoryServiceError: LocalizedError, Equatable {
    case ingredientNotFound
    case unsupportedPresenceDeduction
    case persistenceLoadFailed
    case persistenceSaveFailed

    public var errorDescription: String? {
        switch self {
        case .ingredientNotFound:
            return "This food is no longer in your kitchen. Refresh your kitchen and try again."
        case .unsupportedPresenceDeduction:
            return "This food does not have a measurable amount. Correct the quantity before recording use."
        case .persistenceLoadFailed:
            return "Your saved kitchen couldn’t be loaded, so it was left untouched. Try again."
        case .persistenceSaveFailed:
            return "Your kitchen couldn’t be saved right now. Your changes were not applied. Try again."
        }
    }
}

public struct InventoryUndoState: Sendable {
    var ingredient: Ingredient?
    var eventIDs: [UUID]
    var message: String
}

private enum PersistenceAvailability {
    case ready
    case loadFailed
}

@MainActor
@Observable
public final class InventoryService {
    public private(set) var ingredients: [Ingredient]
    public private(set) var events: [InventoryEvent]
    public var lastMessage: String?
    public var loadErrorMessage: String?
    public var canUndoLastAction: Bool { lastUndoState != nil }

    private let persistence: InventoryPersisting?
    private var lastUndoState: InventoryUndoState?
    private var persistenceAvailability = PersistenceAvailability.ready

    public init(
        persistence: InventoryPersisting? = JSONInventoryPersistence(),
        seedIfEmpty: Bool = true,
        now: Date = .now
    ) {
        self.persistence = persistence

        do {
            if let snapshot = try persistence?.load() {
                ingredients = snapshot.ingredients
                events = snapshot.events
            } else if seedIfEmpty {
                let seededIngredients = SmartFridgeSeedData.ingredients(now: now)
                let seededEvents = seededIngredients.map {
                    InventoryEvent(ingredientID: $0.id, ingredientName: $0.name, kind: .added, note: "Seeded")
                }
                if persistence == nil {
                    ingredients = seededIngredients
                    events = seededEvents
                } else {
                    do {
                        try persistence?.save(InventorySnapshot(ingredients: seededIngredients, events: seededEvents))
                        ingredients = seededIngredients
                        events = seededEvents
                    } catch {
                        ingredients = []
                        events = []
                        loadErrorMessage = InventoryServiceError.persistenceSaveFailed.errorDescription
                    }
                }
            } else {
                ingredients = []
                events = []
            }
        } catch {
            ingredients = []
            events = []
            loadErrorMessage = InventoryServiceError.persistenceLoadFailed.errorDescription
            persistenceAvailability = .loadFailed
        }
    }

    public var activeIngredients: [Ingredient] {
        ingredients
            .filter(\.isActive)
            .sorted { lhs, rhs in
                let left = ExpiryService.state(for: lhs.expiryDate)?.daysUntilExpiry ?? Int.max
                let right = ExpiryService.state(for: rhs.expiryDate)?.daysUntilExpiry ?? Int.max
                if left != right { return left < right }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    public func filteredIngredients(searchText: String, filter: InventoryFilter) -> [Ingredient] {
        activeIngredients.filter { ingredient in
            let matchesStorage = filter.storageLocation == nil || ingredient.storageLocation == filter.storageLocation
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || ingredient.name.localizedCaseInsensitiveContains(query)
                || ingredient.category.displayName.localizedCaseInsensitiveContains(query)
            return matchesStorage && matchesSearch
        }
    }

    public func useSoonIngredients(searchText: String = "", filter: InventoryFilter = .all) -> [Ingredient] {
        IdentifyExpiringInventoryUseCase(repository: self)
            .execute(searchText: searchText, filter: filter)
    }

    public func everythingElse(searchText: String = "", filter: InventoryFilter = .all) -> [Ingredient] {
        let soonIDs = Set(useSoonIngredients(searchText: searchText, filter: filter).map(\.id))
        return filteredIngredients(searchText: searchText, filter: filter).filter { !soonIDs.contains($0.id) }
    }

    @discardableResult
    public func addIngredient(from template: IngredientTemplate, expiryDate: Date? = nil) throws -> Ingredient {
        let date = expiryDate ?? template.expiryOffsetDays.flatMap {
            Calendar.current.date(byAdding: .day, value: $0, to: .now)
        }
        let ingredient = Ingredient(
            name: template.name,
            category: template.category,
            storageLocation: template.storageLocation,
            quantity: template.defaultQuantity,
            expiryDate: date,
            openedState: template.openedState,
            lowStockThreshold: template.lowStockThreshold
        )
        try upsert(ingredient, event: .added, message: "\(ingredient.name) added")
        return ingredient
    }

    public func upsert(_ ingredient: Ingredient, event kind: InventoryEventKind = .edited) throws {
        try upsert(ingredient, event: kind, message: nil)
    }

    public func saveEditedIngredient(_ ingredient: Ingredient, event kind: InventoryEventKind = .edited) throws {
        guard let previous = ingredients.first(where: { $0.id == ingredient.id }) else {
            try upsert(ingredient, event: kind, message: "\(ingredient.name) updated")
            lastMessage = "\(ingredient.name) updated"
            return
        }

        try upsert(ingredient, event: kind, undoIngredient: previous, message: "\(ingredient.name) updated")
    }

    public func saveIngredient(
        _ ingredient: Ingredient,
        event kind: InventoryEventKind = .edited,
        note: String? = nil,
        message: String? = nil
    ) throws {
        guard let previous = ingredients.first(where: { $0.id == ingredient.id }) else {
            try upsert(ingredient, event: kind, note: note, message: message ?? "\(ingredient.name) updated")
            return
        }

        try upsert(ingredient, event: kind, note: note, undoIngredient: previous, message: message ?? "\(ingredient.name) updated")
    }

    public func updateQuantity(for id: UUID, quantity: Quantity) throws {
        guard var ingredient = ingredients.first(where: { $0.id == id }) else {
            throw InventoryServiceError.ingredientNotFound
        }
        let previous = ingredient
        ingredient.quantity = quantity
        try upsert(ingredient, event: .quantityAdjusted, undoIngredient: previous, message: "\(ingredient.name) updated")
    }

    public func useQuantity(for id: UUID, amount: Double, note: String? = nil) throws {
        guard let ingredient = ingredients.first(where: { $0.id == id }) else {
            throw InventoryServiceError.ingredientNotFound
        }
        let previous = ingredient
        let nextQuantity = quantityAfterUsing(amount: amount, from: ingredient.quantity)
        var updated = ingredient
        updated.quantity = nextQuantity
        try upsert(updated, event: .used, note: note ?? "Used \(QuantityFormatter.number(amount))", undoIngredient: previous, message: note ?? "Used \(QuantityFormatter.number(amount))")
    }

    public func adjustQuantity(for id: UUID, delta: Double) throws {
        guard let ingredient = ingredients.first(where: { $0.id == id }) else {
            throw InventoryServiceError.ingredientNotFound
        }
        if case .presence = ingredient.quantity {
            throw InventoryServiceError.unsupportedPresenceDeduction
        }
        if delta < 0 {
            try useQuantity(for: id, amount: abs(delta))
        } else {
            try updateQuantity(for: id, quantity: ingredient.quantity.adjusted(by: delta))
        }
    }

    public func markOpened(_ id: UUID) throws {
        guard var ingredient = ingredients.first(where: { $0.id == id }) else {
            throw InventoryServiceError.ingredientNotFound
        }
        let previous = ingredient
        ingredient.openedState = .opened
        try upsert(ingredient, event: .opened, undoIngredient: previous, message: "\(ingredient.name) marked opened")
    }

    public func markFinished(_ id: UUID) throws {
        guard var ingredient = ingredients.first(where: { $0.id == id }) else {
            throw InventoryServiceError.ingredientNotFound
        }
        let previous = ingredient
        ingredient.status = .finished
        try upsert(ingredient, event: .finished, undoIngredient: previous, message: "\(ingredient.name) finished")
    }

    public func finishIngredient(_ ingredient: Ingredient) throws {
        guard let previous = ingredients.first(where: { $0.id == ingredient.id }) else {
            throw InventoryServiceError.ingredientNotFound
        }
        var updated = ingredient
        updated.status = .finished
        try upsert(updated, event: .finished, undoIngredient: previous, message: "\(updated.name) finished")
    }

    public func markDiscarded(_ id: UUID) throws {
        try updateStatus(id, status: .discarded, event: .discarded, messageSuffix: "discarded")
    }

    public func delete(_ id: UUID) throws {
        guard let ingredient = ingredients.first(where: { $0.id == id }) else {
            throw InventoryServiceError.ingredientNotFound
        }
        var candidateIngredients = ingredients
        candidateIngredients.removeAll { $0.id == id }
        var candidateEvents = events
        candidateEvents.append(makeEvent(.deleted, for: ingredient))
        try publish(ingredients: candidateIngredients, events: candidateEvents, undoState: lastUndoState, message: "\(ingredient.name) deleted")
    }

    public func undoLastAction() throws {
        guard let undo = lastUndoState else { return }
        var candidateIngredients = ingredients
        var candidateEvents = events
        if let ingredient = undo.ingredient {
            if let index = candidateIngredients.firstIndex(where: { $0.id == ingredient.id }) {
                candidateIngredients[index] = ingredient
            } else {
                candidateIngredients.append(ingredient)
            }
        }
        if !undo.eventIDs.isEmpty {
            let eventIDs = Set(undo.eventIDs)
            candidateEvents.removeAll { eventIDs.contains($0.id) }
        }
        try publish(ingredients: candidateIngredients, events: candidateEvents, undoState: nil, message: undo.message)
    }

    public func undoLastRemoval(for id: UUID) throws {
        try undoLastAction()
    }

    public func applyDeductions(_ consumptions: [IngredientConsumption]) throws {
        for consumption in consumptions {
            try useQuantity(for: consumption.ingredientID, amount: abs(consumption.amount))
        }
    }

    public func history(for ingredientID: UUID) -> [InventoryEvent] {
        events
            .filter { $0.ingredientID == ingredientID }
            .sorted { $0.date > $1.date }
    }

    private func updateStatus(_ id: UUID, status: InventoryStatus, event: InventoryEventKind, messageSuffix: String) throws {
        guard var ingredient = ingredients.first(where: { $0.id == id }) else {
            throw InventoryServiceError.ingredientNotFound
        }
        let previous = ingredient
        ingredient.status = status
        try upsert(ingredient, event: event, undoIngredient: previous, message: "\(ingredient.name) marked as \(messageSuffix)")
    }

    private func upsert(
        _ ingredient: Ingredient,
        event kind: InventoryEventKind,
        note: String? = nil,
        undoIngredient: Ingredient? = nil,
        message: String?
    ) throws {
        var updated = ingredient
        updated.lastUpdated = .now
        var candidateIngredients = ingredients
        if let index = candidateIngredients.firstIndex(where: { $0.id == ingredient.id }) {
            candidateIngredients[index] = updated
        } else {
            candidateIngredients.append(updated)
        }
        try upsert(
            updated,
            activities: [InventoryActivityChange(kind: kind, note: note)],
            undoIngredient: undoIngredient,
            message: message
        )
    }

    private func upsert(
        _ ingredient: Ingredient,
        activities activityChanges: [InventoryActivityChange],
        undoIngredient: Ingredient? = nil,
        message: String?
    ) throws {
        var updated = ingredient
        updated.lastUpdated = .now
        var candidateIngredients = ingredients
        if let index = candidateIngredients.firstIndex(where: { $0.id == ingredient.id }) {
            candidateIngredients[index] = updated
        } else {
            candidateIngredients.append(updated)
        }
        let newEvents = activityChanges.map { makeEvent($0.kind, for: updated, note: $0.note) }
        var candidateEvents = events
        candidateEvents.append(contentsOf: newEvents)
        let candidateUndoState: InventoryUndoState?
        if let undoIngredient {
            candidateUndoState = InventoryUndoState(
                ingredient: undoIngredient,
                eventIDs: newEvents.map(\.id),
                message: "\(updated.name) restored"
            )
        } else {
            candidateUndoState = lastUndoState
        }
        try publish(ingredients: candidateIngredients, events: candidateEvents, undoState: candidateUndoState, message: message)
    }

    private func makeEvent(_ kind: InventoryEventKind, for ingredient: Ingredient, note: String? = nil) -> InventoryEvent {
        InventoryEvent(
            ingredientID: ingredient.id,
            ingredientName: ingredient.name,
            kind: kind,
            note: note ?? ingredient.quantity.displayText
        )
    }

    private func quantityAfterUsing(amount: Double, from quantity: Quantity) -> Quantity {
        switch quantity {
        case .count(let value, let unit):
            return .count(max(0, value - Int(amount.rounded())), unit: unit)
        case .measure(let value, let unit):
            return .measure(max(0, value - amount), unit: unit)
        case .package(let count, let unit, let level):
            let current = Double(count) * level.rawValue
            let remaining = max(0, current - amount)
            let ratio = count == 0 ? 0 : remaining / Double(count)
            let nextLevel = PackageLevel.allCases.min {
                abs($0.rawValue - ratio) < abs($1.rawValue - ratio)
            } ?? .almostEmpty
            return .package(count: count, unit: unit, level: nextLevel)
        case .presence(let level):
            switch level {
            case .plenty:
                return .presence(.some)
            case .some, .available:
                return .presence(.low)
            case .low:
                return .presence(.low)
            }
        }
    }

    private func publish(
        ingredients candidateIngredients: [Ingredient],
        events candidateEvents: [InventoryEvent],
        undoState candidateUndoState: InventoryUndoState?,
        message: String?
    ) throws {
        guard persistenceAvailability == .ready else {
            throw InventoryServiceError.persistenceLoadFailed
        }
        do {
            try persistence?.save(InventorySnapshot(ingredients: candidateIngredients, events: candidateEvents))
        } catch {
            throw InventoryServiceError.persistenceSaveFailed
        }
        ingredients = candidateIngredients
        events = candidateEvents
        lastUndoState = candidateUndoState
        lastMessage = message
    }
}

extension InventoryService: HouseholdInventoryRepository {
    public var inventoryItems: [InventoryItem] {
        ingredients
    }

    public var inventoryActivities: [InventoryActivity] {
        events
    }

    public func activeInventoryItems() -> [InventoryItem] {
        activeIngredients
    }

    public func inventoryItem(id: UUID) -> InventoryItem? {
        ingredients.first { $0.id == id }
    }

    public func saveInventoryItem(
        _ item: InventoryItem,
        activity: InventoryEventKind,
        note: String?,
        message: String?
    ) throws {
        try saveInventoryItem(item, activities: [InventoryActivityChange(kind: activity, note: note)], message: message)
    }

    public func saveInventoryItem(
        _ item: InventoryItem,
        activities: [InventoryActivityChange],
        message: String?
    ) throws {
        guard let previous = ingredients.first(where: { $0.id == item.id }) else {
            try upsert(item, activities: activities, message: message ?? "\(item.name) updated")
            return
        }

        try upsert(item, activities: activities, undoIngredient: previous, message: message ?? "\(item.name) updated")
    }

    public func removeFromActiveInventory(_ item: InventoryItem, outcome: FoodOutcome) throws {
        var updated = item
        updated.status = outcome.status
        try saveIngredient(updated, event: outcome.eventKind, message: "\(updated.name) \(outcome == .finished ? "finished" : "discarded")")
    }

    public func deleteInventoryRecord(id: UUID) throws {
        try delete(id)
    }

    public func activities(for itemID: UUID) -> [InventoryActivity] {
        history(for: itemID)
    }
}
