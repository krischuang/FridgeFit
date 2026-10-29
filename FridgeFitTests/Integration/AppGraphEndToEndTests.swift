//
//  AppGraphEndToEndTests.swift
//  FridgeFitTests
//
//  End-to-end flows through the **real composition root**.
//
//  Every other suite exercises one type with its collaborators faked. These
//  build an actual `AppDependencies` - the same object `FridgeFitApp`
//  constructs at launch - over an in-memory (or temporary on-disk) SwiftData
//  container, and drive it through the view models the screens use.
//
//  That is deliberately a different kind of coverage. A unit test proves
//  `SwiftDataPantryRepository` scopes by owner; only this proves that the
//  graph *as assembled* hands the pantry, the activity log, saved recipes
//  and the money stores the same owner and the same container - which is the
//  class of bug that produced "the pantry is local but its prices are in the
//  cloud".
//

import SwiftData
import XCTest
@testable import FridgeFit

@MainActor
final class AppGraphEndToEndTests: XCTestCase {

    /// Who the graph thinks is signed in. Mutable so a test can switch
    /// accounts the way signing out and back in does.
    private var currentUID: String?

    private func makeDependencies(uid: String? = "alice") throws -> AppDependencies {
        currentUID = uid
        return try AppDependencies(
            backend: .swiftData,
            storage: .inMemory,
            ownerIDProvider: { [weak self] in self?.currentUID }
        )
    }

    private func request(_ name: String, quantity: Int = 1) -> AddInventoryItemRequest {
        AddInventoryItemRequest(
            name: name,
            category: .other,
            storageLocation: .fridge,
            quantity: .count(quantity)
        )
    }

    // MARK: - Pantry CRUD through the graph

    func test_pantry_createReadUpdateDelete_throughTheRealGraph() async throws {
        let dependencies = try makeDependencies()
        let inventory = InventoryStore(
            pantryRepository: dependencies.pantryRepository,
            eventRepository: dependencies.eventRepository
        )

        // Create
        try await inventory.add(request("Milk", quantity: 2))
        await inventory.load()
        XCTAssertEqual(inventory.items.map(\.name), ["Milk"])

        // Read
        let stored = try XCTUnwrap(inventory.items.first)
        XCTAssertEqual(stored.quantity, 2)

        // Update
        try await inventory.adjustQuantity(of: stored.id, by: 3)
        await inventory.load()
        XCTAssertEqual(inventory.items.first?.quantity, 5)

        // Delete
        try await inventory.deleteRecord(for: stored.id)
        await inventory.load()
        XCTAssertTrue(inventory.items.isEmpty)
    }

    /// Adding food writes an activity event through a *different* repository
    /// in the same container. If the graph handed them different contexts,
    /// the link between an item and its history would silently not exist.
    func test_pantryAndActivityLog_shareOneStore() async throws {
        let dependencies = try makeDependencies()
        let inventory = InventoryStore(
            pantryRepository: dependencies.pantryRepository,
            eventRepository: dependencies.eventRepository
        )

        try await inventory.add(request("Eggs"))
        await inventory.load()

        let item = try XCTUnwrap(inventory.items.first)
        XCTAssertFalse(inventory.events.isEmpty, "adding food recorded no activity")
        XCTAssertEqual(inventory.history(for: item.id).map(\.itemName), ["Eggs"])
    }

    // MARK: - Restart persistence

    /// The thing an in-memory store can never demonstrate: data surviving
    /// the whole dependency graph being torn down and rebuilt over the same
    /// file, which is what relaunching the app does.
    func test_pantryAndFunds_surviveRebuildingTheEntireGraph() async throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("app-graph-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }

        currentUID = "alice"
        let budget = FoodBudget(limit: aud(Decimal(string: "320.50")!), cadence: .weekly, startDate: TestDates.anchor)

        // First launch.
        do {
            let dependencies = try AppDependencies(
                backend: .swiftData,
                storage: .file(storeURL),
                ownerIDProvider: { [weak self] in self?.currentUID }
            )
            let inventory = InventoryStore(
                pantryRepository: dependencies.pantryRepository,
                eventRepository: dependencies.eventRepository
            )
            try await inventory.add(request("Rice", quantity: 4))

            try await dependencies.fundsEnvironment.budgetStore.saveBudget(budget)
            try await dependencies.fundsEnvironment.budgetStore.addSpend(
                GrocerySpend(amount: aud(Decimal(string: "35.25")!), spentOn: TestDates.anchor, store: "Coles")
            )
        }

        // Second launch, same file, a brand-new graph.
        let relaunched = try AppDependencies(
            backend: .swiftData,
            storage: .file(storeURL),
            ownerIDProvider: { [weak self] in self?.currentUID }
        )
        let inventory = InventoryStore(
            pantryRepository: relaunched.pantryRepository,
            eventRepository: relaunched.eventRepository
        )
        await inventory.load()
        await relaunched.fundsEnvironment.reload()

        XCTAssertEqual(inventory.items.map(\.name), ["Rice"])
        XCTAssertEqual(inventory.items.first?.quantity, 4)
        XCTAssertEqual(
            relaunched.fundsEnvironment.budgetStore.activeBudget()?.limit,
            aud(Decimal(string: "320.50")!),
            "the budget did not survive relaunch"
        )
        XCTAssertEqual(
            relaunched.fundsEnvironment.budgetStore.allSpends().first?.amount,
            aud(Decimal(string: "35.25")!)
        )
    }

    // MARK: - Funds persistence through the graph

    /// The regression from the previous pass: the shipping build must keep
    /// the money beside the pantry, not in the cloud.
    ///
    /// `async` deliberately, like every other test here. A *synchronous*
    /// `@MainActor` test that builds an `AppDependencies` and lets it go in
    /// the same frame tears the SwiftData `ModelContainer` down inside that
    /// frame, and the test host dies with
    /// `malloc: pointer being freed was not allocated`. Awaiting once lets
    /// the container outlive the synchronous scope. The assertions are
    /// unchanged - this is about when the container is released, not what is
    /// checked.
    func test_inSwiftDataMode_theFundsEnvironmentIsLocal() async throws {
        let dependencies = try makeDependencies()
        await Task.yield()

        XCTAssertTrue(
            dependencies.fundsEnvironment.budgetStore is SwiftDataBudgetStore,
            "the shipping build must not put FridgeFunds in Firestore"
        )
        XCTAssertTrue(dependencies.fundsEnvironment.priceStore is SwiftDataItemPriceStore)
        XCTAssertTrue(dependencies.fundsEnvironment.priceBook is SwiftDataPriceBookStore)
    }

    func test_budgetAndSpending_persistThroughTheImpactViewModel() async throws {
        let dependencies = try makeDependencies()
        let viewModel = ImpactBudgetViewModel(funds: dependencies.fundsEnvironment)

        await viewModel.saveBudget(
            limit: 200, currency: .aud, cadence: .weekly, startDate: TestDates.anchor, events: []
        )
        await viewModel.logSpend(amount: 45, spentOn: TestDates.anchor, store: "Woolworths", events: [])

        XCTAssertNil(viewModel.actionError)
        XCTAssertEqual(viewModel.summary.budget?.budget.limit, Money(200, .aud))
        XCTAssertEqual(viewModel.summary.budget?.totalSpent, Money(45, .aud))

        // And it is really in the store, not just in the view model.
        let reread = ImpactBudgetViewModel(funds: dependencies.fundsEnvironment)
        await reread.refresh(events: [])
        XCTAssertEqual(reread.summary.budget?.totalSpent, Money(45, .aud))
    }

    // MARK: - Account isolation across the whole graph

    /// User A / User B isolation, checked across *every* store the graph
    /// owns rather than one at a time. Switching the owner is what signing
    /// out and in as someone else does.
    func test_twoAccountsOnOneDevice_shareNothing() async throws {
        let dependencies = try makeDependencies(uid: "alice")

        let aliceInventory = InventoryStore(
            pantryRepository: dependencies.pantryRepository,
            eventRepository: dependencies.eventRepository
        )
        try await aliceInventory.add(request("Alice Milk"))
        try await dependencies.fundsEnvironment.budgetStore.saveBudget(
            FoodBudget(limit: aud(320), cadence: .weekly, startDate: TestDates.anchor)
        )
        try await dependencies.savedRecipeRepository?.save(
            Recipe(title: "Alice Soup", summary: "", ingredients: [], instructions: []),
            sourceRecipeID: 1
        )

        // Sign out, sign in as Bob. Same graph, same device, same store file.
        currentUID = "bob"

        let bobInventory = InventoryStore(
            pantryRepository: dependencies.pantryRepository,
            eventRepository: dependencies.eventRepository
        )
        await bobInventory.load()
        await dependencies.fundsEnvironment.reload()

        XCTAssertTrue(bobInventory.items.isEmpty, "Bob can see Alice's pantry")
        XCTAssertTrue(bobInventory.events.isEmpty, "Bob can see Alice's activity")
        XCTAssertNil(
            dependencies.fundsEnvironment.budgetStore.activeBudget(),
            "Bob can see Alice's budget"
        )
        let bobRecipes = try await dependencies.savedRecipeRepository?.fetchAll() ?? []
        XCTAssertTrue(bobRecipes.isEmpty, "Bob can see Alice's saved recipes")

        // Bob's own data does not leak back the other way.
        try await bobInventory.add(request("Bob Eggs"))

        currentUID = "alice"
        await aliceInventory.load()
        await dependencies.fundsEnvironment.reload()

        XCTAssertEqual(aliceInventory.items.map(\.name), ["Alice Milk"])
        XCTAssertEqual(dependencies.fundsEnvironment.budgetStore.activeBudget()?.limit, aud(320))
    }

    /// Deleting one account through the real graph must leave the other's
    /// kitchen untouched - the local-store equivalent of the cross-account
    /// isolation the emulator suite checks for Firestore.
    func test_deletingOneAccount_leavesTheOtherIntact() async throws {
        let dependencies = try makeDependencies(uid: "alice")

        let inventory = InventoryStore(
            pantryRepository: dependencies.pantryRepository,
            eventRepository: dependencies.eventRepository
        )
        try await inventory.add(request("Alice Milk"))
        try await dependencies.fundsEnvironment.budgetStore.saveBudget(
            FoodBudget(limit: aud(320), cadence: .weekly, startDate: TestDates.anchor)
        )

        currentUID = "bob"
        try await inventory.add(request("Bob Eggs"))
        try await dependencies.fundsEnvironment.budgetStore.saveBudget(
            FoodBudget(limit: aud(90), cadence: .weekly, startDate: TestDates.anchor)
        )

        // Delete Alice's local data only, through the same deleter the app
        // builds - not a hand-assembled one, which would prove nothing about
        // the real wiring.
        try await dependencies.makeLocalAccountDataDeleter().deleteAllData(ownedBy: "alice")

        // Bob is untouched.
        currentUID = "bob"
        await inventory.load()
        await dependencies.fundsEnvironment.reload()
        XCTAssertEqual(inventory.items.map(\.name), ["Bob Eggs"])
        XCTAssertEqual(dependencies.fundsEnvironment.budgetStore.activeBudget()?.limit, aud(90))

        // Alice is gone.
        currentUID = "alice"
        await inventory.load()
        await dependencies.fundsEnvironment.reload()
        XCTAssertTrue(inventory.items.isEmpty)
        XCTAssertNil(dependencies.fundsEnvironment.budgetStore.activeBudget())
    }

    // MARK: - Signed out

    /// With nobody signed in there is no owner to scope data to, so the
    /// graph must refuse to write rather than storing it somewhere arbitrary
    /// that the next user would inherit.
    func test_signedOut_writesAreRefusedRatherThanStoredUnscoped() async throws {
        let dependencies = try makeDependencies(uid: nil)
        let inventory = InventoryStore(
            pantryRepository: dependencies.pantryRepository,
            eventRepository: dependencies.eventRepository
        )

        do {
            try await inventory.add(request("Orphan Milk"))
            XCTFail("a signed-out write should not succeed")
        } catch {
            // Expected.
        }

        // And nothing was left behind for the next account to find.
        currentUID = "alice"
        await inventory.load()
        XCTAssertTrue(inventory.items.isEmpty, "a signed-out write leaked into the next account")
    }

    func test_signedOut_fundsWritesAreRefused() async throws {
        let dependencies = try makeDependencies(uid: nil)

        await assertThrowsAsync(
            try await dependencies.fundsEnvironment.budgetStore.saveBudget(
                FoodBudget(limit: aud(100), cadence: .weekly, startDate: TestDates.anchor)
            )
        ) { error in
            XCTAssertEqual(error as? PantryRepositoryError, .notAuthenticated)
        }
    }

    // MARK: - Storage disclosure matches the graph

    /// Settings states where the data is. That statement must match what the
    /// graph actually built, which is the coupling the disclosure type
    /// exists to guarantee.
    /// `async` for the same reason as
    /// `test_inSwiftDataMode_theFundsEnvironmentIsLocal`.
    func test_settingsDisclosureMatchesTheGraphThatWasBuilt() async throws {
        let dependencies = try makeDependencies()
        await Task.yield()
        let disclosures = StorageDisclosure.all(for: dependencies.backend)

        let kitchen = try XCTUnwrap(disclosures.first { $0.title.contains("Pantry") })
        XCTAssertEqual(kitchen.location, .onDeviceOnly)
        XCTAssertTrue(dependencies.pantryRepository is SwiftDataPantryRepository)

        let money = try XCTUnwrap(disclosures.first { $0.title.contains("Budget") })
        XCTAssertEqual(money.location, .onDeviceOnly)
        XCTAssertTrue(dependencies.fundsEnvironment.budgetStore is SwiftDataBudgetStore)
    }
}
