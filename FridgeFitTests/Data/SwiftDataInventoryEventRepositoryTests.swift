//
//  SwiftDataInventoryEventRepositoryTests.swift
//  FridgeFitTests
//

import SwiftData
import XCTest
@testable import FridgeFit

/// Integration tests for the SwiftData activity log.
@MainActor
final class SwiftDataInventoryEventRepositoryTests: XCTestCase {
    private var container: PersistenceContainer!
    private var sut: SwiftDataInventoryEventRepository!
    private var pantry: SwiftDataPantryRepository!

    private let owner = "owner-under-test"

    override func setUp() async throws {
        try await super.setUp()
        container = try PersistenceContainer(storage: .inMemory)
        sut = SwiftDataInventoryEventRepository(context: container.mainContext, ownerIDProvider: { [owner] in owner })
        pantry = SwiftDataPantryRepository(context: container.mainContext, ownerIDProvider: { [owner] in owner })
    }

    override func tearDown() async throws {
        sut = nil
        pantry = nil
        container = nil
        try await super.tearDown()
    }

    private func event(
        _ kind: InventoryEventKind,
        name: String = "Milk",
        note: String? = nil,
        date: Date = Date(timeIntervalSince1970: 1_800_000_000),
        itemID: UUID = UUID()
    ) -> InventoryEvent {
        InventoryEvent(pantryItemID: itemID, itemName: name, kind: kind, note: note, date: date)
    }

    func test_append_thenFetchAll_roundTripsEveryField() async throws {
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        let original = event(.discarded, name: "Spinach", note: "Half a bag", date: date)

        try await sut.append(original)
        let fetched = try await sut.fetchAll(limit: 10)
        let stored = try XCTUnwrap(fetched.first)

        XCTAssertEqual(stored.id, original.id)
        XCTAssertEqual(stored.pantryItemID, original.pantryItemID)
        XCTAssertEqual(stored.itemName, "Spinach")
        XCTAssertEqual(stored.kind, .discarded)
        XCTAssertEqual(stored.note, "Half a bag")
        XCTAssertEqual(stored.date, date)
    }

    /// An absent note and a stored empty string are different facts, and the
    /// activity list distinguishes them.
    func test_append_withoutANote_readsBackAsNilNotEmptyString() async throws {
        try await sut.append(event(.opened))

        let fetched = try await sut.fetchAll(limit: 10)
        let stored = try XCTUnwrap(fetched.first)
        XCTAssertNil(stored.note)
    }

    func test_fetchAll_onEmptyStore_returnsEmpty() async throws {
        let stored = try await sut.fetchAll(limit: 50)
        XCTAssertTrue(stored.isEmpty)
    }

    func test_fetchAll_isNewestFirst() async throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        try await sut.append(event(.added, name: "Oldest", date: base))
        try await sut.append(event(.used, name: "Newest", date: base + 200))
        try await sut.append(event(.opened, name: "Middle", date: base + 100))

        let names = try await sut.fetchAll(limit: 50).map(\.itemName)

        XCTAssertEqual(names, ["Newest", "Middle", "Oldest"])
    }

    /// The limit is applied by the fetch rather than after it - the log only
    /// grows, so reading all of it to show the newest few would get slower
    /// every time the user cooks.
    func test_fetchAll_appliesTheLimitToTheNewestEvents() async throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<10 {
            try await sut.append(event(.used, name: "Event \(index)", date: base + Double(index)))
        }

        let limited = try await sut.fetchAll(limit: 3)

        XCTAssertEqual(limited.map(\.itemName), ["Event 9", "Event 8", "Event 7"])
    }

    // MARK: - Undo

    func test_remove_deletesOnlyTheNamedEvents() async throws {
        let keep = event(.added, name: "Keep")
        let drop = event(.used, name: "Drop")
        try await sut.append(keep)
        try await sut.append(drop)

        try await sut.remove(ids: [drop.id])

        let remaining = try await sut.fetchAll(limit: 50)
        XCTAssertEqual(remaining.map(\.itemName), ["Keep"])
    }

    /// Undo is a best-effort correction. Failing it because one event had
    /// already gone would leave the user stuck with an undo button that
    /// never works.
    func test_remove_ignoresIDsThatAreNotPresent() async throws {
        let existing = event(.added)
        try await sut.append(existing)

        try await sut.remove(ids: [existing.id, UUID(), UUID()])

        let stored = try await sut.fetchAll(limit: 50)
        XCTAssertTrue(stored.isEmpty)
    }

    func test_remove_withNoIDs_doesNothing() async throws {
        try await sut.append(event(.added))

        try await sut.remove(ids: [])

        let remaining = try await sut.fetchAll(limit: 50)
        XCTAssertEqual(remaining.count, 1)
    }

    // MARK: - Owner isolation

    func test_eventsAreScopedToTheirOwner() async throws {
        let other = SwiftDataInventoryEventRepository(
            context: container.mainContext,
            ownerIDProvider: { "someone-else" }
        )

        try await sut.append(event(.added, name: "Mine"))
        try await other.append(event(.added, name: "Theirs"))

        let mine = try await sut.fetchAll(limit: 50)
        let theirs = try await other.fetchAll(limit: 50)
        XCTAssertEqual(mine.map(\.itemName), ["Mine"])
        XCTAssertEqual(theirs.map(\.itemName), ["Theirs"])
    }

    /// Undo must not reach across accounts either.
    func test_anotherOwnerCannotRemoveYourEvents() async throws {
        let other = SwiftDataInventoryEventRepository(
            context: container.mainContext,
            ownerIDProvider: { "someone-else" }
        )
        let mine = event(.added, name: "Mine")
        try await sut.append(mine)

        try await other.remove(ids: [mine.id])

        let remaining = try await sut.fetchAll(limit: 50)
        XCTAssertEqual(remaining.count, 1, "Still there")
    }

    func test_withoutAnOwner_everyOperationThrowsNotAuthenticated() async throws {
        let unauthenticated = SwiftDataInventoryEventRepository(
            context: container.mainContext,
            ownerIDProvider: { nil }
        )

        await assertThrowsNotAuthenticated { _ = try await unauthenticated.fetchAll(limit: 10) }
        await assertThrowsNotAuthenticated { try await unauthenticated.append(self.event(.added)) }
        await assertThrowsNotAuthenticated { try await unauthenticated.remove(ids: [UUID()]) }
    }

    // MARK: - Relationship

    /// `finished` and `discarded` events are written *after* the pantry item
    /// is removed, so their relationship is legitimately nil. The event still
    /// has to carry enough to read correctly, which is why `pantryItemID` and
    /// `itemName` are stored on it rather than reached through the link.
    func test_appendingAnEventForAnAlreadyRemovedItem_stillRecordsIt() async throws {
        let item = PantryItem(ingredient: Ingredient(name: "Milk"), quantity: 1, unit: .liters)
        try await pantry.add(item)
        try await pantry.remove(id: item.id)

        try await sut.append(
            InventoryEvent(pantryItemID: item.id, itemName: item.name, kind: .finished, note: "1 L")
        )

        let fetched = try await sut.fetchAll(limit: 10)
        let stored = try XCTUnwrap(fetched.first)
        XCTAssertEqual(stored.kind, .finished)
        XCTAssertEqual(stored.itemName, "Milk")
        XCTAssertEqual(stored.pantryItemID, item.id)
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
