//
//  SwiftDataPersistenceRetentionTests.swift
//  FridgeFitTests
//

import SwiftData
import XCTest
@testable import FridgeFit

/// Proves data survives the app being quit and reopened.
///
/// This is the one claim the rest of the suite cannot make. Every other test
/// here uses an in-memory container, and an in-memory store would pass a
/// "write then read" test while persisting nothing - which is exactly the
/// failure mode a native-persistence requirement is asking about.
///
/// So these tests use a **real file** in a temporary directory, write through
/// one `ModelContainer`, tear it down, and build a *second* container over the
/// same file. That is as close to a relaunch as a unit test can get: the
/// second container shares no context, no cache and no object graph with the
/// first, so anything it reads came off the disk.
///
/// The file is deleted on teardown, so nothing leaks between runs.
@MainActor
final class SwiftDataPersistenceRetentionTests: XCTestCase {
    private var storeURL: URL!
    private let owner = "owner-under-test"

    override func setUp() async throws {
        try await super.setUp()
        storeURL = URL.temporaryDirectory.appending(path: "fridgefit-retention-\(UUID().uuidString).store")
    }

    override func tearDown() async throws {
        // SwiftData writes sidecar files beside the store; remove them too so
        // a later run cannot inherit anything.
        let manager = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            if manager.fileExists(atPath: url.path) {
                try? manager.removeItem(at: url)
            }
        }
        storeURL = nil
        try await super.tearDown()
    }

    /// A container over `storeURL`, and the two repositories on it.
    ///
    /// Returning the container matters: when the caller lets it go, the
    /// context goes with it, which is what makes the next call a genuine
    /// cold read.
    private func openStore() throws -> (
        container: PersistenceContainer,
        pantry: SwiftDataPantryRepository,
        events: SwiftDataInventoryEventRepository
    ) {
        let container = try PersistenceContainer(storage: .file(storeURL))
        return (
            container,
            SwiftDataPantryRepository(context: container.mainContext, ownerIDProvider: { [owner] in owner }),
            SwiftDataInventoryEventRepository(context: container.mainContext, ownerIDProvider: { [owner] in owner })
        )
    }

    /// Add an item, close the store, reopen it, and the item is still there.
    ///
    /// This is the automated form of the live demonstration: add an
    /// ingredient, terminate the app, relaunch, and find it still in the
    /// Kitchen with no network involved.
    func test_pantryItemSurvivesTheStoreBeingClosedAndReopened() async throws {
        let item = PantryItem(
            ingredient: Ingredient(name: "Greek Yogurt", category: .dairy),
            quantity: 2,
            unit: .pieces,
            expiryDate: Date(timeIntervalSince1970: 1_800_000_000),
            storageLocation: .fridge
        )

        // "Launch 1"
        do {
            let store = try openStore()
            try await store.pantry.add(item)
            let written = try await store.pantry.fetchAll()
            XCTAssertEqual(written.count, 1)
        }

        // "Launch 2" - a brand-new container over the same file.
        let reopened = try openStore()
        let stored = try await reopened.pantry.fetchAll()

        XCTAssertEqual(stored.count, 1, "The item must come back off the disk")
        let read = try XCTUnwrap(stored.first)
        XCTAssertEqual(read.id, item.id)
        XCTAssertEqual(read.name, "Greek Yogurt")
        XCTAssertEqual(read.quantity, 2)
        XCTAssertEqual(read.storageLocation, .fridge)
        XCTAssertEqual(read.expiryDate, item.expiryDate)
    }

    /// Edits persist too, not just inserts - and the edit replaces the
    /// original rather than adding a second row.
    func test_anUpdateSurvivesReopening() async throws {
        var item = PantryItem(ingredient: Ingredient(name: "Milk"), quantity: 2, unit: .liters)

        do {
            let store = try openStore()
            try await store.pantry.add(item)
            item.quantity = 1
            item.openedState = .opened
            try await store.pantry.update(item)
        }

        let reopened = try openStore()
        let stored = try await reopened.pantry.fetchAll()

        XCTAssertEqual(stored.count, 1, "Update must not have inserted a duplicate")
        XCTAssertEqual(stored.first?.quantity, 1)
        XCTAssertEqual(stored.first?.openedState, .opened)
    }

    /// A deletion persists as well. Worth asserting separately: a store that
    /// "forgot" a delete on reopen would quietly resurrect food the user
    /// threw away, and the pantry would start claiming they have it.
    func test_aDeletionSurvivesReopening() async throws {
        let item = PantryItem(ingredient: Ingredient(name: "Eggs"), quantity: 6, unit: .pieces)

        do {
            let store = try openStore()
            try await store.pantry.add(item)
            try await store.pantry.remove(id: item.id)
        }

        let reopened = try openStore()
        let afterDelete = try await reopened.pantry.fetchAll()
        XCTAssertTrue(afterDelete.isEmpty, "A delete must not come back")
    }

    /// The activity log and the relationship between an event and its item
    /// both survive, so history is still readable after a relaunch.
    func test_historyAndItsRelationshipSurviveReopening() async throws {
        let item = PantryItem(ingredient: Ingredient(name: "Cheese"), quantity: 200, unit: .grams)

        do {
            let store = try openStore()
            try await store.pantry.add(item)
            try await store.events.append(
                InventoryEvent(pantryItemID: item.id, itemName: item.name, kind: .added, note: "200 g")
            )
        }

        let reopened = try openStore()
        let history = try await reopened.events.fetchAll(limit: 50)

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.kind, .added)
        XCTAssertEqual(history.first?.note, "200 g")

        let entities = try reopened.container.mainContext.fetch(FetchDescriptor<PantryItemEntity>())
        XCTAssertEqual(entities.first?.events.count, 1, "The relationship is stored, not just in memory")
    }

    /// Owner scoping is stored, not a runtime filter over an unscoped file.
    /// After a reopen, a different account still sees nothing.
    func test_ownerScopingSurvivesReopening() async throws {
        do {
            let store = try openStore()
            try await store.pantry.add(
                PantryItem(ingredient: Ingredient(name: "Mine"), quantity: 1, unit: .pieces)
            )
        }

        let reopened = try openStore()
        let other = SwiftDataPantryRepository(
            context: reopened.container.mainContext,
            ownerIDProvider: { "someone-else" }
        )

        let mine = try await reopened.pantry.fetchAll()
        let theirs = try await other.fetchAll()
        XCTAssertEqual(mine.map(\.name), ["Mine"])
        XCTAssertTrue(theirs.isEmpty, "A second account sees an empty pantry, not yours")
    }
}
