//
//  SwiftDataPantryRepositoryTests.swift
//  FridgeFitTests
//

import SwiftData
import XCTest
@testable import FridgeFit

/// Integration tests for the SwiftData pantry, against a real `ModelContainer`.
///
/// These deliberately do **not** use a mock. `InMemoryPantryRepository` already
/// proves the use cases' logic; what needs proving here is that the database
/// itself does what the protocol promises - that a unique id is really unique,
/// that a predicate really filters, and that deleting an item really leaves
/// its history behind. None of that is observable through an array-backed
/// double.
///
/// The container is in-memory per test (nothing leaks between cases, nothing
/// is left on disk). The one thing an in-memory store cannot demonstrate -
/// surviving a relaunch - is covered separately by
/// `SwiftDataPersistenceRetentionTests`.
@MainActor
final class SwiftDataPantryRepositoryTests: XCTestCase {
    private var container: PersistenceContainer!
    private var sut: SwiftDataPantryRepository!
    private var events: SwiftDataInventoryEventRepository!

    private let owner = "owner-under-test"

    override func setUp() async throws {
        try await super.setUp()
        container = try PersistenceContainer(storage: .inMemory)
        sut = SwiftDataPantryRepository(context: container.mainContext, ownerIDProvider: { [owner] in owner })
        events = SwiftDataInventoryEventRepository(context: container.mainContext, ownerIDProvider: { [owner] in owner })
    }

    override func tearDown() async throws {
        sut = nil
        events = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Create and read

    /// Every stored field survives the round trip, including all six optional
    /// kitchen fields. A mapper that silently dropped one would still pass a
    /// test that only checked the name.
    func test_add_thenFetchAll_roundTripsEveryField() async throws {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        let item = PantryItem(
            ingredient: Ingredient(name: "Greek Yogurt", category: .dairy),
            quantity: 0.5,
            unit: .kilograms,
            expiryDate: expiry,
            storageLocation: .fridge,
            openedState: .opened,
            lowStockThreshold: 0.2,
            packageUnit: .tub,
            packageLevel: .half
        )

        try await sut.add(item)
        let stored = try await sut.fetchAll()

        XCTAssertEqual(stored.count, 1)
        let read = try XCTUnwrap(stored.first)
        XCTAssertEqual(read.id, item.id)
        XCTAssertEqual(read.ingredient.name, "Greek Yogurt")
        XCTAssertEqual(read.ingredient.category, .dairy)
        XCTAssertEqual(read.quantity, 0.5)
        XCTAssertEqual(read.unit, .kilograms)
        XCTAssertEqual(read.expiryDate, expiry)
        XCTAssertEqual(read.storageLocation, .fridge)
        XCTAssertEqual(read.openedState, .opened)
        XCTAssertEqual(read.lowStockThreshold, 0.2)
        XCTAssertEqual(read.packageUnit, .tub)
        XCTAssertEqual(read.packageLevel, .half)
    }

    /// An item with no kitchen fields set reads back with `nil` in each one,
    /// rather than invented defaults. This is the shape every item added by
    /// the receipt scanner and the camera review sheet has.
    func test_add_itemWithNoKitchenFields_readsBackAsUntracked() async throws {
        let item = PantryItem(ingredient: Ingredient(name: "Rice"), quantity: 2, unit: .pieces)

        try await sut.add(item)
        let fetched = try await sut.fetchAll()
        let read = try XCTUnwrap(fetched.first)

        XCTAssertNil(read.expiryDate)
        XCTAssertNil(read.storageLocation)
        XCTAssertNil(read.openedState)
        XCTAssertNil(read.lowStockThreshold)
        XCTAssertEqual(read.storage, .pantry, "Display falls back to pantry without storing a claim")
        XCTAssertNil(read.expiryState, "Untracked expiry is not an expiry state")
    }

    func test_fetchAll_onEmptyStore_returnsEmptyAndDoesNotThrow() async throws {
        let stored = try await sut.fetchAll()
        XCTAssertTrue(stored.isEmpty)
    }

    /// Ordering is done by the fetch, matching the `order(by: "ingredientName")`
    /// the Firestore implementation sends, so both backends hand the same
    /// order to the same view models.
    func test_fetchAll_isOrderedByIngredientName() async throws {
        for name in ["Tomato", "Apple", "Milk"] {
            try await sut.add(PantryItem(ingredient: Ingredient(name: name), quantity: 1, unit: .pieces))
        }

        let names = try await sut.fetchAll().map(\.name)

        XCTAssertEqual(names, ["Apple", "Milk", "Tomato"])
    }

    func test_fetchByID_returnsTheItem_andNilWhenAbsent() async throws {
        let item = PantryItem(ingredient: Ingredient(name: "Butter"), quantity: 1, unit: .pieces)
        try await sut.add(item)

        let found = try await sut.fetch(id: item.id)
        let missing = try await sut.fetch(id: UUID())

        XCTAssertEqual(found?.id, item.id)
        XCTAssertNil(missing)
    }

    // MARK: - Update

    func test_update_changesTheStoredItem() async throws {
        var item = PantryItem(ingredient: Ingredient(name: "Milk"), quantity: 2, unit: .liters)
        try await sut.add(item)

        item.quantity = 1
        item.storageLocation = .fridge
        try await sut.update(item)

        let found = try await sut.fetch(id: item.id)
        let read = try XCTUnwrap(found)
        let all = try await sut.fetchAll()
        XCTAssertEqual(read.quantity, 1)
        XCTAssertEqual(read.storageLocation, .fridge)
        XCTAssertEqual(all.count, 1, "Update must not insert a second row")
    }

    /// Clearing an optional field has to actually clear it. The Firestore
    /// implementation needs `FieldValue.delete()` for this; here it needs
    /// every field assigned on update. A mapper that skipped `nil`s would
    /// leave the item claiming an expiry date the user just removed.
    func test_update_clearingExpiryDate_actuallyClearsIt() async throws {
        var item = PantryItem(
            ingredient: Ingredient(name: "Yoghurt"),
            quantity: 1,
            unit: .pieces,
            expiryDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await sut.add(item)

        item.expiryDate = nil
        try await sut.update(item)

        let found = try await sut.fetch(id: item.id)
        let read = try XCTUnwrap(found)
        XCTAssertNil(read.expiryDate)
    }

    /// Error parity with `FirestorePantryRepository`, which throws the same
    /// case. Use cases and view models assert on this error, so a backend
    /// that threw something else would change behaviour above the protocol.
    func test_update_missingItem_throwsItemNotFound() async throws {
        let absent = PantryItem(ingredient: Ingredient(name: "Ghost"), quantity: 1, unit: .pieces)

        do {
            try await sut.update(absent)
            XCTFail("Expected itemNotFound")
        } catch let error as UpdatePantryItemError {
            XCTAssertEqual(error, .itemNotFound)
        }
    }

    // MARK: - Delete

    func test_remove_deletesTheItem() async throws {
        let item = PantryItem(ingredient: Ingredient(name: "Eggs"), quantity: 6, unit: .pieces)
        try await sut.add(item)

        try await sut.remove(id: item.id)

        let remaining = try await sut.fetchAll()
        XCTAssertTrue(remaining.isEmpty)
    }

    func test_remove_missingItem_throwsPantryItemNotFound() async throws {
        do {
            try await sut.remove(id: UUID())
            XCTFail("Expected pantryItemNotFound")
        } catch let error as RemovePantryItemError {
            XCTAssertEqual(error, .pantryItemNotFound)
        }
    }

    // MARK: - Relationship integrity

    /// The delete rule, which is the one piece of this schema that would be a
    /// bug if it were the obvious choice.
    ///
    /// `RecordFoodOutcomeUseCase` removes the pantry item and *then* writes
    /// the event saying it was finished. Under `.cascade`, that delete would
    /// take the event with it and the activity history would be permanently
    /// empty for exactly the actions users most want to see. So the
    /// relationship nullifies, and the event survives with its own copy of
    /// the item's id and name.
    func test_deletingAnItem_keepsItsHistory() async throws {
        let item = PantryItem(ingredient: Ingredient(name: "Milk"), quantity: 1, unit: .liters)
        try await sut.add(item)
        try await events.append(
            InventoryEvent(pantryItemID: item.id, itemName: item.name, kind: .added, note: "1 L")
        )

        try await sut.remove(id: item.id)

        let history = try await events.fetchAll(limit: 50)
        XCTAssertEqual(history.count, 1, "History must outlive the item it describes")
        XCTAssertEqual(history.first?.pantryItemID, item.id)
        XCTAssertEqual(history.first?.itemName, "Milk")

        // And the relationship itself is nullified, not dangling.
        let descriptor = FetchDescriptor<InventoryEventEntity>()
        let stored = try container.mainContext.fetch(descriptor)
        XCTAssertEqual(stored.count, 1)
        XCTAssertNil(stored.first?.item, "The relationship nullifies on delete")
    }

    /// Appending an event while the item still exists links the two, so the
    /// relationship is genuinely populated rather than always nil.
    func test_appendingAnEvent_linksItToItsItem() async throws {
        let item = PantryItem(ingredient: Ingredient(name: "Cheese"), quantity: 200, unit: .grams)
        try await sut.add(item)

        try await events.append(
            InventoryEvent(pantryItemID: item.id, itemName: item.name, kind: .used, note: "Used 50 g")
        )

        let stored = try container.mainContext.fetch(FetchDescriptor<PantryItemEntity>())
        XCTAssertEqual(stored.first?.events.count, 1, "The item knows its own history")
        XCTAssertEqual(stored.first?.events.first?.kind, InventoryEventKind.used.rawValue)
    }

    // MARK: - Domain predicates

    /// Undated items are excluded rather than sorted last: an item nobody
    /// dated is not urgent, it is untracked. Same rule
    /// `IdentifyExpiringInventoryUseCase` applies in memory.
    func test_fetchExpiring_excludesUndatedItems_andOrdersSoonestFirst() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400

        try await sut.add(PantryItem(
            ingredient: Ingredient(name: "Spinach"), quantity: 1, unit: .pieces,
            expiryDate: now + day
        ))
        try await sut.add(PantryItem(
            ingredient: Ingredient(name: "Chicken"), quantity: 1, unit: .pieces,
            expiryDate: now - day
        ))
        try await sut.add(PantryItem(
            ingredient: Ingredient(name: "Pasta"), quantity: 1, unit: .pieces,
            expiryDate: now + (30 * day)
        ))
        try await sut.add(PantryItem(
            ingredient: Ingredient(name: "Salt"), quantity: 1, unit: .pieces
        ))

        let urgent = try await sut.fetchExpiring(before: now + (3 * day))

        XCTAssertEqual(urgent.map(\.name), ["Chicken", "Spinach"])
        XCTAssertFalse(urgent.map(\.name).contains("Salt"), "Undated is untracked, not urgent")
        XCTAssertFalse(urgent.map(\.name).contains("Pasta"), "Outside the window")
    }

    // MARK: - Owner isolation

    /// Two accounts on one device must not see each other's food.
    ///
    /// Firestore gets this from the `users/{uid}` path and its security
    /// rules. A local SQLite file has neither, so the scoping is a column
    /// plus a clause in every query - and this test is what proves the clause
    /// is actually there on the read path.
    func test_itemsAreScopedToTheirOwner() async throws {
        let other = SwiftDataPantryRepository(
            context: container.mainContext,
            ownerIDProvider: { "someone-else" }
        )

        try await sut.add(PantryItem(ingredient: Ingredient(name: "My Milk"), quantity: 1, unit: .liters))
        try await other.add(PantryItem(ingredient: Ingredient(name: "Their Milk"), quantity: 1, unit: .liters))

        let mine = try await sut.fetchAll()
        let theirs = try await other.fetchAll()
        XCTAssertEqual(mine.map(\.name), ["My Milk"])
        XCTAssertEqual(theirs.map(\.name), ["Their Milk"])
    }

    /// Knowing an id is not authorisation. Without the owner clause on the
    /// write path, signing in as a second account would let that account
    /// mutate the first one's rows.
    func test_anotherOwnerCannotUpdateOrRemoveYourItem() async throws {
        let other = SwiftDataPantryRepository(
            context: container.mainContext,
            ownerIDProvider: { "someone-else" }
        )
        var item = PantryItem(ingredient: Ingredient(name: "Mine"), quantity: 1, unit: .pieces)
        try await sut.add(item)

        item.quantity = 99
        do {
            try await other.update(item)
            XCTFail("Expected itemNotFound for another owner's item")
        } catch let error as UpdatePantryItemError {
            XCTAssertEqual(error, .itemNotFound)
        }

        do {
            try await other.remove(id: item.id)
            XCTFail("Expected pantryItemNotFound for another owner's item")
        } catch let error as RemovePantryItemError {
            XCTAssertEqual(error, .pantryItemNotFound)
        }

        let untouched = try await sut.fetch(id: item.id)
        XCTAssertEqual(untouched?.quantity, 1, "Untouched")
    }

    /// Refuses rather than falling back to an unscoped query, exactly as
    /// `FirestorePantryRepository` refuses when there is no signed-in uid.
    func test_withoutAnOwner_everyOperationThrowsNotAuthenticated() async throws {
        let unauthenticated = SwiftDataPantryRepository(
            context: container.mainContext,
            ownerIDProvider: { nil }
        )
        let item = PantryItem(ingredient: Ingredient(name: "Anything"), quantity: 1, unit: .pieces)

        await assertThrowsNotAuthenticated { _ = try await unauthenticated.fetchAll() }
        await assertThrowsNotAuthenticated { _ = try await unauthenticated.fetch(id: item.id) }
        await assertThrowsNotAuthenticated { _ = try await unauthenticated.fetchExpiring(before: .now) }
        await assertThrowsNotAuthenticated { try await unauthenticated.add(item) }
        await assertThrowsNotAuthenticated { try await unauthenticated.update(item) }
        await assertThrowsNotAuthenticated { try await unauthenticated.remove(id: item.id) }
    }

    /// An empty-string uid is treated as no uid, not as a valid owner -
    /// otherwise every signed-out device would share one "" pantry.
    func test_emptyOwnerIDIsTreatedAsNotAuthenticated() async throws {
        let blank = SwiftDataPantryRepository(
            context: container.mainContext,
            ownerIDProvider: { "" }
        )
        await assertThrowsNotAuthenticated { _ = try await blank.fetchAll() }
    }

    private func assertThrowsNotAuthenticated(
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected notAuthenticated", file: file, line: line)
        } catch let error as PantryRepositoryError {
            XCTAssertEqual(error, .notAuthenticated, file: file, line: line)
        } catch {
            XCTFail("Expected PantryRepositoryError, got \(error)", file: file, line: line)
        }
    }
}
