//
//  InventoryStoreTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class InventoryStoreTests: XCTestCase {

    private func makeStore(
        seedItems: [PantryItem] = []
    ) -> (InventoryStore, InMemoryPantryRepository, InMemoryInventoryEventRepository) {
        let pantry = InMemoryPantryRepository(seedItems: seedItems)
        let events = InMemoryInventoryEventRepository()
        return (InventoryStore(pantryRepository: pantry, eventRepository: events), pantry, events)
    }

    private func item(_ name: String, quantity: Double = 6, unit: MeasurementUnit = .pieces, daysToExpiry: Int? = nil) -> PantryItem {
        PantryItem(
            ingredient: Ingredient(name: name, category: .other),
            quantity: quantity,
            unit: unit,
            expiryDate: daysToExpiry.map { Calendar.current.date(byAdding: .day, value: $0, to: .now)! },
            storageLocation: .fridge
        )
    }

    // MARK: - Loading

    func test_load_readsTheSamePantryEveryOtherTabReads() async {
        let (store, _, _) = makeStore(seedItems: [item("Eggs"), item("Milk")])

        await store.load()

        XCTAssertEqual(store.items.count, 2)
        XCTAssertNil(store.errorMessage)
    }

    func test_load_ordersBySoonestExpiry_withUndatedLast() async {
        let (store, _, _) = makeStore(seedItems: [
            item("Undated"),
            item("Later", daysToExpiry: 10),
            item("Urgent", daysToExpiry: 1),
        ])

        await store.load()

        XCTAssertEqual(store.items.map(\.name), ["Urgent", "Later", "Undated"])
    }

    func test_load_surfacesAPantryFailure() async {
        let store = InventoryStore(
            pantryRepository: FailingPantryRepository(),
            eventRepository: InMemoryInventoryEventRepository()
        )

        await store.load()

        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.items.isEmpty)
    }

    func test_load_doesNotReportAnErrorWhenOnlyHistoryFails() async {
        // The food list is fine; claiming otherwise would imply it is wrong.
        let store = InventoryStore(
            pantryRepository: InMemoryPantryRepository(seedItems: [item("Eggs")]),
            eventRepository: FailingEventRepository()
        )

        await store.load()

        XCTAssertEqual(store.items.count, 1)
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertNil(store.errorMessage)
    }

    // MARK: - Undo

    func test_undo_restoresTheAmountAfterAUse() async throws {
        let existing = item("Eggs", quantity: 6)
        let (store, pantry, _) = makeStore(seedItems: [existing])
        await store.load()

        try await store.recordUse(of: existing.id, amount: 2)
        let actual1 = try await pantry.fetchAll().first?.quantity
        XCTAssertEqual(actual1, 4)

        await store.undoLastAction()

        let actual2 = try await pantry.fetchAll().first?.quantity
        XCTAssertEqual(actual2, 6)
    }

    func test_undo_deletesTheEventsTheUndoneActionWrote() async throws {
        // An action the user took back did not happen, so the log must not
        // keep implying it did.
        let existing = item("Eggs", quantity: 6)
        let (store, _, events) = makeStore(seedItems: [existing])
        await store.load()

        try await store.recordUse(of: existing.id, amount: 2)
        let actual3 = try await events.fetchAll(limit: 100).count
        XCTAssertEqual(actual3, 1)

        await store.undoLastAction()

        let actual4 = try await events.fetchAll(limit: 100).count
        XCTAssertEqual(actual4, 0)
    }

    func test_undo_putsBackAnItemThatWasFinished() async throws {
        let existing = item("Milk", quantity: 1, unit: .liters)
        let (store, pantry, _) = makeStore(seedItems: [existing])
        await store.load()

        try await store.record(outcome: .finished, for: existing.id)
        let actual5 = try await pantry.fetchAll().isEmpty
        XCTAssertTrue(actual5)

        await store.undoLastAction()

        let restored = try await pantry.fetchAll()
        XCTAssertEqual(restored.count, 1)
        // Restored under its original id, so its history still points at it.
        XCTAssertEqual(restored.first?.id, existing.id)
        XCTAssertEqual(restored.first?.quantity, 1)
    }

    func test_undo_removesAnItemThatWasJustAdded() async throws {
        let (store, pantry, _) = makeStore()
        await store.load()

        try await store.add(AddInventoryItemRequest(
            name: "Eggs",
            category: .dairy,
            storageLocation: .fridge,
            quantity: .count(6)
        ))
        let actual6 = try await pantry.fetchAll().count
        XCTAssertEqual(actual6, 1)

        await store.undoLastAction()

        let actual7 = try await pantry.fetchAll().isEmpty
        XCTAssertTrue(actual7)
    }

    func test_undo_isUnavailableUntilSomethingHappens() async {
        let (store, _, _) = makeStore(seedItems: [item("Eggs")])
        await store.load()

        XCTAssertFalse(store.canUndoLastAction)
    }

    func test_undo_isConsumedByUsingIt() async throws {
        let existing = item("Eggs")
        let (store, _, _) = makeStore(seedItems: [existing])
        await store.load()

        try await store.recordUse(of: existing.id, amount: 1)
        XCTAssertTrue(store.canUndoLastAction)

        await store.undoLastAction()

        XCTAssertFalse(store.canUndoLastAction)
    }

    // MARK: - Adjusting

    func test_adjustingDown_isRecordedAsUse() async throws {
        let existing = item("Eggs", quantity: 6)
        let (store, _, events) = makeStore(seedItems: [existing])
        await store.load()

        try await store.adjustQuantity(of: existing.id, by: -1)

        let actual8 = try await events.fetchAll(limit: 10).first?.kind
        XCTAssertEqual(actual8, .used)
    }

    func test_adjustingUp_isRecordedAsACorrection() async throws {
        // You cannot un-eat food, so adding is always a correction.
        let existing = item("Eggs", quantity: 6)
        let (store, pantry, events) = makeStore(seedItems: [existing])
        await store.load()

        try await store.adjustQuantity(of: existing.id, by: 2)

        let actual9 = try await pantry.fetchAll().first?.quantity
        XCTAssertEqual(actual9, 8)
        let actual10 = try await events.fetchAll(limit: 10).first?.kind
        XCTAssertEqual(actual10, .quantityAdjusted)
    }

    // MARK: - Drawer saves

    func test_drawerSave_appliesDetailsAndAUseAsOneUndoableAction() async throws {
        let existing = item("Milk", quantity: 2, unit: .liters)
        let (store, pantry, events) = makeStore(seedItems: [existing])
        await store.load()

        try await store.saveDrawerChanges(
            details: UpdateInventoryItemDetailsRequest(
                itemID: existing.id,
                name: "Oat Milk",
                category: .dairy,
                storageLocation: .fridge,
                quantity: .measure(2, unit: .liters),
                expiryDate: nil,
                openedState: .notApplicable,
                lowStockThreshold: nil
            ),
            includeDetails: true,
            usedAmount: 0.5
        )

        let stored = try await pantry.fetchAll().first
        XCTAssertEqual(stored?.name, "Oat Milk")
        XCTAssertEqual(stored?.quantity, 1.5)
        // Two things happened, so two events were written...
        let actual11 = try await events.fetchAll(limit: 100).count
        XCTAssertEqual(actual11, 2)

        // ...and one undo takes the whole save back.
        await store.undoLastAction()

        let restored = try await pantry.fetchAll().first
        XCTAssertEqual(restored?.name, "Milk")
        XCTAssertEqual(restored?.quantity, 2)
        let actual12 = try await events.fetchAll(limit: 100).count
        XCTAssertEqual(actual12, 0)
    }

    func test_drawerSave_doesNothingWhenThereIsNothingToSave() async throws {
        let existing = item("Milk", quantity: 2, unit: .liters)
        let (store, _, events) = makeStore(seedItems: [existing])
        await store.load()

        try await store.saveDrawerChanges(
            details: UpdateInventoryItemDetailsRequest(
                itemID: existing.id,
                name: "Milk",
                category: .other,
                storageLocation: .fridge,
                quantity: .measure(2, unit: .liters),
                expiryDate: nil,
                openedState: .notApplicable,
                lowStockThreshold: nil
            ),
            includeDetails: false,
            usedAmount: 0
        )

        let actual13 = try await events.fetchAll(limit: 100).isEmpty
        XCTAssertTrue(actual13)
        XCTAssertFalse(store.canUndoLastAction)
    }

    // MARK: - History

    func test_history_isScopedToOneItem_newestFirst() async throws {
        let eggs = item("Eggs", quantity: 6)
        let milk = item("Milk", quantity: 2, unit: .liters)
        let (store, _, _) = makeStore(seedItems: [eggs, milk])
        await store.load()

        try await store.recordUse(of: eggs.id, amount: 1)
        try await store.recordUse(of: milk.id, amount: 1)
        try await store.recordUse(of: eggs.id, amount: 1)

        let eggsHistory = store.history(for: eggs.id)
        XCTAssertEqual(eggsHistory.count, 2)
        XCTAssertTrue(eggsHistory.allSatisfy { $0.pantryItemID == eggs.id })
        XCTAssertGreaterThanOrEqual(eggsHistory[0].date, eggsHistory[1].date)
    }
}

// MARK: - Test doubles

private final class FailingPantryRepository: PantryRepository {
    func fetchAll() async throws -> [PantryItem] { throw PantryRepositoryError.notAuthenticated }
    func add(_ item: PantryItem) async throws { throw PantryRepositoryError.notAuthenticated }
    func update(_ item: PantryItem) async throws { throw PantryRepositoryError.notAuthenticated }
    func remove(id: UUID) async throws { throw PantryRepositoryError.notAuthenticated }
}

private final class FailingEventRepository: InventoryEventRepository {
    func fetchAll(limit: Int) async throws -> [InventoryEvent] { throw PantryRepositoryError.notAuthenticated }
    func append(_ event: InventoryEvent) async throws { throw PantryRepositoryError.notAuthenticated }
    func remove(ids: [UUID]) async throws { throw PantryRepositoryError.notAuthenticated }
}
