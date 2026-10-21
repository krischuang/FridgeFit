//
//  PantryRepositoryContractTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// One set of assertions, run against every `PantryRepository` implementation.
///
/// ## Why this exists
///
/// The use cases and view models are written against the protocol, so they
/// behave identically only as long as the implementations do. Nothing
/// enforced that before: `InMemoryPantryRepository` threw
/// `UpdatePantryItemError.itemNotFound` because someone wrote it that way,
/// and `FirestorePantryRepository` did too, by coincidence of both authors
/// reading the same doc comment. A third implementation could easily have
/// thrown something else, and the failure would have surfaced as a view model
/// showing the wrong message - not as a red test.
///
/// This is also what keeps the Firebase adapter honest as SwiftData becomes
/// the default. A preserved backend that nobody runs rots quietly; a
/// preserved backend with a shared contract suite does not.
///
/// ## How to add an implementation
///
/// Subclass, override `makeRepository()`. The base class returns `nil` and so
/// reports nothing of its own - XCTest runs the base class too, and a base
/// that asserted would fail for a repository that does not exist.
///
/// Every test is `async`: building a `@MainActor` repository from a
/// synchronous XCTest method aborts the host (see
/// `PersistenceConfigurationTests` for the narrowing).
@MainActor
class PantryRepositoryContractTests: XCTestCase {

    /// The implementation under test, or `nil` in the abstract base.
    func makeRepository() -> (any PantryRepository)? { nil }

    private func item(
        _ name: String,
        quantity: Double = 1,
        unit: MeasurementUnit = .pieces,
        expiryDate: Date? = nil
    ) -> PantryItem {
        PantryItem(
            ingredient: Ingredient(name: name),
            quantity: quantity,
            unit: unit,
            expiryDate: expiryDate
        )
    }

    // MARK: - Reading

    func test_contract_emptyStore_returnsNoItemsAndDoesNotThrow() async throws {
        guard let sut = makeRepository() else { return }

        let items = try await sut.fetchAll()

        XCTAssertTrue(items.isEmpty)
    }

    func test_contract_addedItemIsReturnedByFetchAll() async throws {
        guard let sut = makeRepository() else { return }
        let milk = item("Milk", quantity: 2, unit: .liters)

        try await sut.add(milk)
        let items = try await sut.fetchAll()

        XCTAssertEqual(items.map(\.id), [milk.id])
        XCTAssertEqual(items.first?.quantity, 2)
        XCTAssertEqual(items.first?.unit, .liters)
    }

    func test_contract_fetchByID_findsAnAddedItem() async throws {
        guard let sut = makeRepository() else { return }
        let milk = item("Milk")
        try await sut.add(milk)

        let found = try await sut.fetch(id: milk.id)

        XCTAssertEqual(found?.id, milk.id)
    }

    /// `nil`, not an error. "Not there" is an ordinary answer to this
    /// question - the use cases that call it decide whether that is a
    /// problem.
    func test_contract_fetchByID_returnsNilForAnUnknownID() async throws {
        guard let sut = makeRepository() else { return }

        let found = try await sut.fetch(id: UUID())

        XCTAssertNil(found)
    }

    // MARK: - Domain predicate

    /// Undated items are excluded, not ordered last. Every backend has to
    /// agree on this, because `IdentifyExpiringInventoryUseCase` applies the
    /// same rule in memory and the Kitchen's "Use First" section would
    /// disagree with itself otherwise.
    func test_contract_fetchExpiring_excludesUndatedItems() async throws {
        guard let sut = makeRepository() else { return }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400

        try await sut.add(item("Spinach", expiryDate: now + day))
        try await sut.add(item("Salt"))

        let expiring = try await sut.fetchExpiring(before: now + (3 * day))

        XCTAssertEqual(expiring.map(\.name), ["Spinach"])
    }

    func test_contract_fetchExpiring_isOrderedSoonestFirst() async throws {
        guard let sut = makeRepository() else { return }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400

        try await sut.add(item("Later", expiryDate: now + (2 * day)))
        try await sut.add(item("Sooner", expiryDate: now - day))

        let expiring = try await sut.fetchExpiring(before: now + (3 * day))

        XCTAssertEqual(expiring.map(\.name), ["Sooner", "Later"])
    }

    func test_contract_fetchExpiring_excludesItemsOutsideTheWindow() async throws {
        guard let sut = makeRepository() else { return }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400

        try await sut.add(item("Pasta", expiryDate: now + (30 * day)))

        let expiring = try await sut.fetchExpiring(before: now + (3 * day))

        XCTAssertTrue(expiring.isEmpty)
    }

    // MARK: - Updating

    func test_contract_updateChangesTheStoredItem_withoutAddingARow() async throws {
        guard let sut = makeRepository() else { return }
        var milk = item("Milk", quantity: 2, unit: .liters)
        try await sut.add(milk)

        milk.quantity = 1
        try await sut.update(milk)

        let items = try await sut.fetchAll()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.quantity, 1)
    }

    /// The error every backend must throw, because `InventoryStore` and the
    /// inventory use cases are written against this exact case.
    func test_contract_updatingAnUnknownItem_throwsItemNotFound() async throws {
        guard let sut = makeRepository() else { return }

        do {
            try await sut.update(item("Ghost"))
            XCTFail("Expected UpdatePantryItemError.itemNotFound")
        } catch let error as UpdatePantryItemError {
            XCTAssertEqual(error, .itemNotFound)
        }
    }

    // MARK: - Removing

    func test_contract_removeDeletesTheItem() async throws {
        guard let sut = makeRepository() else { return }
        let eggs = item("Eggs", quantity: 6)
        try await sut.add(eggs)

        try await sut.remove(id: eggs.id)

        let items = try await sut.fetchAll()
        XCTAssertTrue(items.isEmpty)
    }

    func test_contract_removingAnUnknownItem_throwsPantryItemNotFound() async throws {
        guard let sut = makeRepository() else { return }

        do {
            try await sut.remove(id: UUID())
            XCTFail("Expected RemovePantryItemError.pantryItemNotFound")
        } catch let error as RemovePantryItemError {
            XCTAssertEqual(error, .pantryItemNotFound)
        }
    }

    /// Re-adding a removed item under its original id has to work: it is how
    /// `InventoryStore.undoLastAction()` restores food the user finished or
    /// discarded, and the id must survive so the item's history still points
    /// at the right thing.
    func test_contract_anItemCanBeRestoredUnderItsOriginalID() async throws {
        guard let sut = makeRepository() else { return }
        let milk = item("Milk")
        try await sut.add(milk)
        try await sut.remove(id: milk.id)

        try await sut.add(milk)

        let items = try await sut.fetchAll()
        XCTAssertEqual(items.map(\.id), [milk.id])
    }

    // MARK: - Round-tripping the optional fields

    /// The kitchen fields are all optional and all absent on legacy items, so
    /// every backend has to keep "not tracked" distinct from a value.
    func test_contract_optionalFieldsRoundTripAndStayAbsentWhenUnset() async throws {
        guard let sut = makeRepository() else { return }
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        let tracked = PantryItem(
            ingredient: Ingredient(name: "Yoghurt", category: .dairy),
            quantity: 0.5,
            unit: .kilograms,
            expiryDate: expiry,
            storageLocation: .fridge,
            openedState: .opened,
            lowStockThreshold: 0.2
        )
        let untracked = item("Rice")

        try await sut.add(tracked)
        try await sut.add(untracked)

        let stored = try await sut.fetchAll()
        let readTracked = try XCTUnwrap(stored.first { $0.id == tracked.id })
        let readUntracked = try XCTUnwrap(stored.first { $0.id == untracked.id })

        XCTAssertEqual(readTracked.expiryDate, expiry)
        XCTAssertEqual(readTracked.storageLocation, .fridge)
        XCTAssertEqual(readTracked.openedState, .opened)
        XCTAssertEqual(readTracked.lowStockThreshold, 0.2)
        XCTAssertEqual(readTracked.ingredient.category, .dairy)

        XCTAssertNil(readUntracked.expiryDate)
        XCTAssertNil(readUntracked.storageLocation)
        XCTAssertNil(readUntracked.openedState)
        XCTAssertNil(readUntracked.lowStockThreshold)
    }
}

// MARK: - The implementations

/// The test double every use-case test already runs against. Included so a
/// change to the double that drifts from the real backends fails here.
final class InMemoryPantryRepositoryContractTests: PantryRepositoryContractTests {
    override func makeRepository() -> (any PantryRepository)? {
        InMemoryPantryRepository()
    }
}

/// The shipped backend, against a real in-memory `ModelContainer`.
final class SwiftDataPantryRepositoryContractTests: PantryRepositoryContractTests {
    private var container: PersistenceContainer?

    override func makeRepository() -> (any PantryRepository)? {
        guard let container = try? PersistenceContainer(storage: .inMemory) else {
            XCTFail("Could not open an in-memory store")
            return nil
        }
        // Held for the lifetime of the test: the repository keeps only the
        // context, so a deallocated container would pull the store out from
        // under it.
        self.container = container
        return SwiftDataPantryRepository(
            context: container.mainContext,
            ownerIDProvider: { "contract-owner" }
        )
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }
}

// MARK: - Firestore
//
// Deliberately not a subclass. Running this contract against
// `FirestorePantryRepository` needs the Firestore emulator *and* a Firestore
// client, and constructing a client inside this unit-test host aborts the
// process with `malloc: pointer being freed was not allocated` - which is why
// no test in this project has ever instantiated one, and why the three
// Firestore suites test their `encode`/`decode` as pure static functions.
//
// Adding a subclass that could not run would be worse than not having one: it
// would appear in the suite as passing coverage of a backend nobody had
// exercised. The Firestore path is instead verified by `firestore-tests/`
// against the emulator and by launching the app with `-persistence firebase`.
// That gap is recorded in the Phase 4 report rather than hidden here.
