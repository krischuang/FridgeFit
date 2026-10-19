//
//  SwiftDataFundsStoresTests.swift
//  FridgeFitTests
//

import SwiftData
import XCTest
@testable import FridgeFit

// FridgeFunds on the on-device store (the default backend). same setup as
// SwiftDataPantryRepositoryTests: an in-memory container, a fixed owner.
@MainActor
final class SwiftDataFundsStoresTests: XCTestCase {
    private var container: PersistenceContainer!
    private let owner = "owner-under-test"

    override func setUp() async throws {
        try await super.setUp()
        container = try PersistenceContainer(storage: .inMemory)
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private func budgetStore(owner: String? = "owner-under-test") -> SwiftDataBudgetStore {
        SwiftDataBudgetStore(context: container.mainContext, ownerIDProvider: { owner })
    }

    private func priceStore(owner: String? = "owner-under-test") -> SwiftDataItemPriceStore {
        SwiftDataItemPriceStore(context: container.mainContext, ownerIDProvider: { owner })
    }

    func test_budget_roundTrips_andSavingAgainReplacesIt() async {
        let store = budgetStore()
        XCTAssertNil(store.activeBudget())

        let first = FoodBudget(limit: Money(Decimal(string: "120.50")!, .aud), cadence: .weekly, startDate: TestDates.anchor)
        store.saveBudget(first)
        XCTAssertEqual(store.activeBudget(), first)

        // only one active budget per account
        let second = FoodBudget(limit: Money(200, .aud), cadence: .fortnightly, startDate: TestDates.day(7))
        store.saveBudget(second)
        XCTAssertEqual(store.activeBudget(), second)
        let rows = (try? container.mainContext.fetch(FetchDescriptor<FundsBudgetEntity>())) ?? []
        XCTAssertEqual(rows.count, 1)
    }

    func test_spends_roundTrip_inDateOrder() async {
        let store = budgetStore()
        let later = GrocerySpend(amount: Money(Decimal(string: "4.45")!, .aud), spentOn: TestDates.day(2), store: "Coles",
                                 purchasedItemIDs: [PantryItemID("a")], note: "milk run")
        let earlier = GrocerySpend(amount: Money(35, .aud), spentOn: TestDates.day(0))

        store.addSpend(later)
        store.addSpend(earlier)

        XCTAssertEqual(store.allSpends(), [earlier, later])
    }

    func test_waste_roundTrips_andTheOncePerDayRuleStillWorks() async {
        let store = budgetStore()
        let waste = WastedFoodCost(pantryItemID: PantryItemID("milk"), quantityDiscarded: 0.5,
                                   lostAmount: Money(Decimal(string: "2.25")!, .aud),
                                   discardedOn: TestDates.day(1), reason: .expired)

        store.addWasteCost(waste)

        XCTAssertEqual(store.allWasteCosts(), [waste])
        XCTAssertTrue(store.wasteAlreadyRecorded(for: PantryItemID("milk"), on: TestDates.day(1)))
        XCTAssertFalse(store.wasteAlreadyRecorded(for: PantryItemID("milk"), on: TestDates.day(2)))
    }

    func test_itemPrice_roundTrips_andUpdatesInPlace() async {
        let store = priceStore()
        let id = PantryItemID("eggs")

        store.save(ItemPriceInfo(pantryItemID: id, unitCost: Money(Decimal(string: "0.45")!, .aud)))
        store.save(ItemPriceInfo(pantryItemID: id, unitCost: Money(Decimal(string: "0.5")!, .aud)))

        XCTAssertEqual(store.info(for: id)?.unitCost, Money(Decimal(string: "0.5")!, .aud))
        let rows = (try? container.mainContext.fetch(FetchDescriptor<ItemPriceEntity>())) ?? []
        XCTAssertEqual(rows.count, 1)
    }

    func test_clearingAPrice_isRemembered() async {
        let store = priceStore()
        let id = PantryItemID("bread")
        store.save(ItemPriceInfo(pantryItemID: id, unitCost: Money(4, .aud)))

        store.save(ItemPriceInfo(pantryItemID: id, unitCost: nil))

        XCTAssertNil(store.info(for: id)?.unitCost)
    }

    // same boundary as the pantry: one account never sees another's numbers
    func test_dataIsScopedToTheOwner() async {
        budgetStore(owner: "alice").saveBudget(FoodBudget(limit: Money(100, .aud), cadence: .weekly, startDate: TestDates.anchor))
        budgetStore(owner: "alice").addSpend(GrocerySpend(amount: Money(10, .aud), spentOn: TestDates.anchor))
        priceStore(owner: "alice").save(ItemPriceInfo(pantryItemID: PantryItemID("x"), unitCost: Money(1, .aud)))

        let bob = budgetStore(owner: "bob")
        XCTAssertNil(bob.activeBudget())
        XCTAssertTrue(bob.allSpends().isEmpty)
        XCTAssertNil(priceStore(owner: "bob").info(for: PantryItemID("x")))
    }

    func test_signedOut_readsNothing_andWritesNothing() async {
        let signedOut = budgetStore(owner: nil)

        signedOut.saveBudget(FoodBudget(limit: Money(100, .aud), cadence: .weekly, startDate: TestDates.anchor))
        signedOut.addSpend(GrocerySpend(amount: Money(10, .aud), spentOn: TestDates.anchor))
        priceStore(owner: nil).save(ItemPriceInfo(pantryItemID: PantryItemID("x"), unitCost: Money(1, .aud)))

        XCTAssertNil(signedOut.activeBudget())
        let spendRows = (try? container.mainContext.fetch(FetchDescriptor<GrocerySpendEntity>())) ?? []
        let priceRows = (try? container.mainContext.fetch(FetchDescriptor<ItemPriceEntity>())) ?? []
        XCTAssertTrue(spendRows.isEmpty)
        XCTAssertTrue(priceRows.isEmpty)
    }

    // the whole thing on SwiftData: pantry + Budget tab in one store
    func test_environment_onSwiftData_valuesTheRealPantry() async throws {
        let pantry = SwiftDataPantryRepository(context: container.mainContext, ownerIDProvider: { [owner] in owner })
        let eggs = PantryItem(ingredient: Ingredient(name: "Eggs"), quantity: 12, unit: .pieces)
        try await pantry.add(eggs)
        let environment = FundsEnvironment.swiftData(pantryRepository: pantry, context: container.mainContext,
                                                     ownerIDProvider: { [owner] in owner })
        environment.budgetStore.saveBudget(makeWeeklyBudget(limit: 100))
        FundsPurchasePriceRecorder(environment: environment).recordPurchasePrice(6, for: eggs)

        let viewModel = MoneyInFridgeViewModel(environment: environment)
        await viewModel.reload()

        XCTAssertEqual(viewModel.items.map(\.name), ["Eggs"])
        XCTAssertEqual(viewModel.valuation?.totalValue, Money(6, .aud))
    }

    func test_matching_picksSwiftData_forTheSwiftDataBackend() async throws {
        let dependencies = try AppDependencies(backend: .swiftData, storage: .inMemory, ownerIDProvider: { [owner] in owner })

        let environment = FundsEnvironment.matching(dependencies)

        XCTAssertTrue(environment.budgetStore is SwiftDataBudgetStore)
        XCTAssertTrue(environment.priceStore is SwiftDataItemPriceStore)
    }
}
