//
//  SwiftDataFundsStoreTests.swift
//  FridgeFitTests
//
//  The on-device FridgeFunds stores the shipping build now uses.
//
//  These cover the four things that would be invisible until they bit
//  someone: account scoping, Decimal precision through storage, replace-not-
//  duplicate semantics, and survival across a container being torn down and
//  rebuilt over the same file.
//

import SwiftData
import XCTest
@testable import FridgeFit

@MainActor
final class SwiftDataFundsStoreTests: XCTestCase {

    private var container: PersistenceContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try PersistenceContainer(storage: .inMemory)
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func budgetStore(owner: String?) -> SwiftDataBudgetStore {
        SwiftDataBudgetStore(context: container.mainContext, ownerIDProvider: { owner })
    }

    private func priceStore(owner: String?) -> SwiftDataItemPriceStore {
        SwiftDataItemPriceStore(context: container.mainContext, ownerIDProvider: { owner })
    }

    private func priceBook(owner: String?) -> SwiftDataPriceBookStore {
        SwiftDataPriceBookStore(context: container.mainContext, ownerIDProvider: { owner })
    }

    // MARK: - Round trips

    func test_saveBudget_thenLoad_returnsIt() async throws {
        let store = budgetStore(owner: "alice")
        let budget = FoodBudget(limit: aud(320), cadence: .fortnightly, startDate: TestDates.anchor)

        let outcome = try await store.saveBudget(budget)
        XCTAssertEqual(outcome, .committed)

        let reread = budgetStore(owner: "alice")
        try await reread.load()

        XCTAssertEqual(reread.activeBudget()?.limit, aud(320))
        XCTAssertEqual(reread.activeBudget()?.cadence, .fortnightly)
        XCTAssertEqual(reread.activeBudget()?.id, budget.id)
    }

    func test_addSpendAndWaste_thenLoad_returnsThem() async throws {
        let store = budgetStore(owner: "alice")
        try await store.addSpend(
            GrocerySpend(amount: aud(35), spentOn: TestDates.anchor, store: "Woolworths", note: "weekly shop")
        )
        try await store.addWasteCost(
            WastedFoodCost(
                pantryItemID: PantryItemID("item-1"),
                quantityDiscarded: 2,
                lostAmount: aud(4),
                discardedOn: TestDates.anchor,
                reason: .expired
            )
        )

        let reread = budgetStore(owner: "alice")
        try await reread.load()

        XCTAssertEqual(reread.allSpends().count, 1)
        XCTAssertEqual(reread.allSpends().first?.store, "Woolworths")
        XCTAssertEqual(reread.allSpends().first?.note, "weekly shop")
        XCTAssertEqual(reread.allWasteCosts().count, 1)
        XCTAssertEqual(reread.allWasteCosts().first?.reason, .expired)
        XCTAssertTrue(reread.wasteAlreadyRecorded(for: PantryItemID("item-1"), on: TestDates.anchor))
    }

    func test_priceStoreAndPriceBook_roundTrip() async throws {
        let prices = priceStore(owner: "alice")
        let book = priceBook(owner: "alice")
        let itemID = PantryItemID("item-1")

        try await prices.save(
            ItemPriceInfo(pantryItemID: itemID, unitCost: aud(Decimal(string: "3.80")!), expiryDate: TestDates.day(2))
        )
        try await book.record(
            PriceBookEntry(displayName: "Baby Spinach", unitCost: aud(Decimal(string: "3.80")!), unit: "bag", recordedOn: TestDates.anchor)
        )

        let rereadPrices = priceStore(owner: "alice")
        let rereadBook = priceBook(owner: "alice")
        try await rereadPrices.load()
        try await rereadBook.load()

        XCTAssertEqual(rereadPrices.info(for: itemID)?.unitCost, aud(Decimal(string: "3.80")!))
        XCTAssertEqual(rereadPrices.info(for: itemID)?.expiryDate, TestDates.day(2))
        // Name matching is case- and whitespace-insensitive, same as in-memory.
        XCTAssertEqual(rereadBook.entry(forIngredientNamed: "  baby SPINACH ")?.unitCost, aud(Decimal(string: "3.80")!))
    }

    // MARK: - Decimal precision

    /// The reason money is stored as text. A `Double` round trip turns these
    /// into values the user can see are wrong, and once stored it is
    /// permanent.
    func test_money_survivesStorageExactly() async throws {
        let awkward = [
            Decimal(string: "4.50")!,
            Decimal(string: "0.017")!,
            Decimal(string: "19.99")!,
            Decimal(string: "0.1")!,
            Decimal(string: "123456.78")!,
        ]

        for (index, amount) in awkward.enumerated() {
            let prices = priceStore(owner: "alice")
            let id = PantryItemID("item-\(index)")
            try await prices.save(ItemPriceInfo(pantryItemID: id, unitCost: aud(amount)))

            let reread = priceStore(owner: "alice")
            try await reread.load()

            XCTAssertEqual(
                reread.info(for: id)?.unitCost?.amount,
                amount,
                "\(amount) did not survive the round trip exactly"
            )
        }
    }

    func test_fundsDecimal_doesNotDependOnTheDeviceLocale() {
        // The write side must not emit a decimal comma, because the read side
        // parses POSIX. A device set to a comma locale would otherwise store
        // a price the next launch silently drops.
        let text = FundsDecimal.text(Decimal(string: "4.50")!)
        XCTAssertFalse(text.contains(","), "Stored money must not use a locale separator, got \(text)")
        XCTAssertEqual(FundsDecimal.value(text), Decimal(string: "4.50")!)
        XCTAssertNil(FundsDecimal.value("not a number"))
        XCTAssertNil(FundsDecimal.value(nil))
    }

    // MARK: - Account scoping

    /// Two accounts on one device must not see each other's money. This is
    /// the local equivalent of Firestore's `users/{uid}` boundary, and here
    /// it is only as good as the predicate.
    func test_budgetsAreScopedPerAccount() async throws {
        try await budgetStore(owner: "alice").saveBudget(
            FoodBudget(limit: aud(320), cadence: .weekly, startDate: TestDates.anchor)
        )
        try await budgetStore(owner: "bob").saveBudget(
            FoodBudget(limit: aud(90), cadence: .weekly, startDate: TestDates.anchor)
        )

        let alice = budgetStore(owner: "alice")
        let bob = budgetStore(owner: "bob")
        try await alice.load()
        try await bob.load()

        XCTAssertEqual(alice.activeBudget()?.limit, aud(320))
        XCTAssertEqual(bob.activeBudget()?.limit, aud(90), "Bob must keep his own budget, not Alice's")
    }

    func test_spendsAreScopedPerAccount() async throws {
        try await budgetStore(owner: "alice").addSpend(GrocerySpend(amount: aud(10), spentOn: TestDates.anchor))
        try await budgetStore(owner: "alice").addSpend(GrocerySpend(amount: aud(20), spentOn: TestDates.anchor))
        try await budgetStore(owner: "bob").addSpend(GrocerySpend(amount: aud(5), spentOn: TestDates.anchor))

        let alice = budgetStore(owner: "alice")
        let bob = budgetStore(owner: "bob")
        try await alice.load()
        try await bob.load()

        XCTAssertEqual(alice.allSpends().count, 2)
        XCTAssertEqual(bob.allSpends().count, 1)
        XCTAssertEqual(bob.allSpends().first?.amount, aud(5))
    }

    /// Prices are keyed by `(owner, pantryItemID)`. A predicate on the item
    /// alone would let one account overwrite another's price for the same id.
    func test_itemPricesAreScopedPerAccount_forTheSameItemID() async throws {
        let itemID = PantryItemID("shared-item-id")
        try await priceStore(owner: "alice").save(ItemPriceInfo(pantryItemID: itemID, unitCost: aud(3)))
        try await priceStore(owner: "bob").save(ItemPriceInfo(pantryItemID: itemID, unitCost: aud(8)))

        let alice = priceStore(owner: "alice")
        let bob = priceStore(owner: "bob")
        try await alice.load()
        try await bob.load()

        XCTAssertEqual(alice.info(for: itemID)?.unitCost, aud(3), "Bob's write must not overwrite Alice's price")
        XCTAssertEqual(bob.info(for: itemID)?.unitCost, aud(8))
    }

    func test_priceBookIsScopedPerAccount_forTheSameIngredientName() async throws {
        try await priceBook(owner: "alice").record(
            PriceBookEntry(displayName: "Milk", unitCost: aud(2), unit: "L", recordedOn: TestDates.anchor)
        )
        try await priceBook(owner: "bob").record(
            PriceBookEntry(displayName: "Milk", unitCost: aud(5), unit: "L", recordedOn: TestDates.anchor)
        )

        let alice = priceBook(owner: "alice")
        let bob = priceBook(owner: "bob")
        try await alice.load()
        try await bob.load()

        XCTAssertEqual(alice.entry(forIngredientNamed: "Milk")?.unitCost, aud(2))
        XCTAssertEqual(bob.entry(forIngredientNamed: "Milk")?.unitCost, aud(5))
    }

    // MARK: - Signed out

    /// With no signed-in account there is no owner to scope the row to, so a
    /// write must fail rather than land somewhere arbitrary.
    func test_writesFail_whenNobodyIsSignedIn() async {
        let store = budgetStore(owner: nil)

        await assertThrowsAsync(
            try await store.saveBudget(FoodBudget(limit: aud(100), cadence: .weekly, startDate: TestDates.anchor))
        ) { error in
            XCTAssertEqual(error as? PantryRepositoryError, .notAuthenticated)
        }

        await assertThrowsAsync(try await priceStore(owner: "").save(ItemPriceInfo(pantryItemID: PantryItemID("x"), unitCost: aud(1)))) { error in
            XCTAssertEqual(error as? PantryRepositoryError, .notAuthenticated, "An empty uid is not an owner either")
        }
    }

    // MARK: - Replace, don't duplicate

    /// One budget per account. Saving twice must leave one row, or `load()`
    /// would be picking between two and "which budget am I on" would depend
    /// on fetch order.
    func test_savingTheBudgetTwice_keepsOneBudget() async throws {
        let store = budgetStore(owner: "alice")
        try await store.saveBudget(FoodBudget(limit: aud(100), cadence: .weekly, startDate: TestDates.anchor))
        try await store.saveBudget(FoodBudget(limit: aud(250), cadence: .fortnightly, startDate: TestDates.anchor))

        let reread = budgetStore(owner: "alice")
        try await reread.load()

        XCTAssertEqual(reread.activeBudget()?.limit, aud(250))
        XCTAssertEqual(reread.activeBudget()?.cadence, .fortnightly)

        let rows = try container.mainContext.fetch(FetchDescriptor<FoodBudgetEntity>())
        XCTAssertEqual(rows.count, 1, "A second save must replace the budget, not add one")
    }

    /// Writing the same spend id twice - which is what a retry after a
    /// failure does - must not log the purchase twice.
    func test_writingTheSameSpendTwice_keepsOneRow() async throws {
        let store = budgetStore(owner: "alice")
        let spend = GrocerySpend(amount: aud(35), spentOn: TestDates.anchor, store: "Coles")

        try await store.addSpend(spend)
        try await store.addSpend(spend)

        let reread = budgetStore(owner: "alice")
        try await reread.load()

        XCTAssertEqual(reread.allSpends().count, 1, "Re-writing one spend id must not duplicate it")
    }

    func test_savingAPriceTwice_keepsOneRowAndTheLatestValue() async throws {
        let itemID = PantryItemID("item-1")
        let store = priceStore(owner: "alice")
        try await store.save(ItemPriceInfo(pantryItemID: itemID, unitCost: aud(3)))
        try await store.save(ItemPriceInfo(pantryItemID: itemID, unitCost: aud(4)))

        let reread = priceStore(owner: "alice")
        try await reread.load()

        XCTAssertEqual(reread.info(for: itemID)?.unitCost, aud(4))
        let rows = try container.mainContext.fetch(FetchDescriptor<ItemPriceEntity>())
        XCTAssertEqual(rows.count, 1)
    }

    // MARK: - Corrupt rows

    /// An unparseable amount decodes to `nil` and the row is dropped, rather
    /// than defaulting to zero. A budget silently reading as $0.00 would tell
    /// the user they had overspent everything.
    func test_aBudgetRowWithUnreadableMoney_isDroppedRatherThanReadAsZero() async throws {
        container.mainContext.insert(
            FoodBudgetEntity(
                id: UUID(),
                ownerID: "alice",
                limitAmount: "not a number",
                currency: "AUD",
                cadence: BudgetCadence.weekly.rawValue,
                startDate: TestDates.anchor
            )
        )
        try container.mainContext.save()

        let store = budgetStore(owner: "alice")
        try await store.load()

        XCTAssertNil(store.activeBudget(), "A corrupt budget must read as absent, never as zero")
    }
}

/// Survival across a container being torn down and rebuilt over the same
/// file - the thing an in-memory store can never demonstrate.
@MainActor
final class SwiftDataFundsRelaunchTests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("funds-relaunch-\(UUID().uuidString).store")
    }

    override func tearDownWithError() throws {
        // Remove the store and its SQLite siblings.
        for suffix in ["", "-shm", "-wal"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            try? FileManager.default.removeItem(at: url)
        }
        storeURL = nil
        try super.tearDownWithError()
    }

    func test_budgetAndPrices_surviveAContainerRebuild() async throws {
        let budget = FoodBudget(limit: aud(Decimal(string: "320.50")!), cadence: .fortnightly, startDate: TestDates.anchor)
        let itemID = PantryItemID("item-1")

        do {
            let container = try PersistenceContainer(storage: .file(storeURL))
            let budgets = SwiftDataBudgetStore(context: container.mainContext, ownerIDProvider: { "alice" })
            let prices = SwiftDataItemPriceStore(context: container.mainContext, ownerIDProvider: { "alice" })

            try await budgets.saveBudget(budget)
            try await budgets.addSpend(GrocerySpend(amount: aud(Decimal(string: "35.25")!), spentOn: TestDates.anchor))
            try await prices.save(ItemPriceInfo(pantryItemID: itemID, unitCost: aud(Decimal(string: "3.80")!)))
        }

        // A second container over the same file: the closest a unit test gets
        // to relaunching the app.
        let reopened = try PersistenceContainer(storage: .file(storeURL))
        let budgets = SwiftDataBudgetStore(context: reopened.mainContext, ownerIDProvider: { "alice" })
        let prices = SwiftDataItemPriceStore(context: reopened.mainContext, ownerIDProvider: { "alice" })
        try await budgets.load()
        try await prices.load()

        XCTAssertEqual(budgets.activeBudget()?.limit, aud(Decimal(string: "320.50")!))
        XCTAssertEqual(budgets.activeBudget()?.id, budget.id)
        XCTAssertEqual(budgets.allSpends().first?.amount, aud(Decimal(string: "35.25")!))
        XCTAssertEqual(prices.info(for: itemID)?.unitCost, aud(Decimal(string: "3.80")!))
    }

    /// Signing out and in as somebody else on the same device must show that
    /// account's money, not the previous one's.
    func test_switchingAccounts_showsTheNewAccountsMoney() async throws {
        let container = try PersistenceContainer(storage: .file(storeURL))
        var owner = "alice"
        let store = SwiftDataBudgetStore(context: container.mainContext, ownerIDProvider: { owner })

        try await store.saveBudget(FoodBudget(limit: aud(320), cadence: .weekly, startDate: TestDates.anchor))
        try await store.load()
        XCTAssertEqual(store.activeBudget()?.limit, aud(320))

        owner = "bob"
        try await store.load()
        XCTAssertNil(store.activeBudget(), "Bob has set no budget, so he must see none of Alice's")

        try await store.saveBudget(FoodBudget(limit: aud(90), cadence: .weekly, startDate: TestDates.anchor))
        try await store.load()
        XCTAssertEqual(store.activeBudget()?.limit, aud(90))

        owner = "alice"
        try await store.load()
        XCTAssertEqual(store.activeBudget()?.limit, aud(320), "Alice's budget must still be hers")
    }
}
