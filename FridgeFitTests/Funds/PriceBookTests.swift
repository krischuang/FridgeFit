//
//  PriceBookTests.swift
//  FridgeFitTests
//

import SwiftData
import XCTest
@testable import FridgeFit

// the price book: every recorded price also lands here by ingredient name, on
// each backend, so recipes can price stuff you don't have right now
@MainActor
final class PriceBookTests: XCTestCase {

    func test_inMemory_latestPriceWins_andNameMatchIgnoresCase() async {
        let book = InMemoryPriceBookStore()
        book.record(PriceBookEntry(displayName: "Milk", unitCost: aud(2), unit: "L"))
        book.record(PriceBookEntry(displayName: "milk ", unitCost: Money(Decimal(string: "2.25")!, .aud), unit: "L"))

        XCTAssertEqual(book.entry(forIngredientNamed: "MILK")?.unitCost, Money(Decimal(string: "2.25")!, .aud))
    }

    func test_swiftData_roundTrips_updatesInPlace_andIsScopedToTheOwner() async throws {
        let container = try PersistenceContainer(storage: .inMemory)
        let alice = SwiftDataPriceBookStore(context: container.mainContext, ownerIDProvider: { "alice" })
        let bob = SwiftDataPriceBookStore(context: container.mainContext, ownerIDProvider: { "bob" })

        alice.record(PriceBookEntry(displayName: "Cheddar", unitCost: aud(10), unit: "kg", recordedOn: TestDates.day(0)))
        alice.record(PriceBookEntry(displayName: "Cheddar", unitCost: aud(12), unit: "kg", recordedOn: TestDates.day(3)))

        let entry = try XCTUnwrap(alice.entry(forIngredientNamed: "cheddar"))
        XCTAssertEqual(entry.unitCost, aud(12))
        XCTAssertEqual(entry.unit, "kg")
        XCTAssertEqual(entry.recordedOn, TestDates.day(3))
        XCTAssertNil(bob.entry(forIngredientNamed: "Cheddar"))
        let rows = try container.mainContext.fetch(FetchDescriptor<PriceBookEntity>())
        XCTAssertEqual(rows.count, 1)
    }

    func test_swiftData_signedOut_recordsNothing() async throws {
        let container = try PersistenceContainer(storage: .inMemory)
        let signedOut = SwiftDataPriceBookStore(context: container.mainContext, ownerIDProvider: { nil })

        signedOut.record(PriceBookEntry(displayName: "Milk", unitCost: aud(2), unit: "L"))

        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PriceBookEntity>()).isEmpty)
    }

    func test_firestoreMapping_roundTrips() async {
        let entry = PriceBookEntry(displayName: "Chicken Breast", unitCost: Money(Decimal(string: "0.017")!, .aud),
                                   unit: "g", recordedOn: TestDates.day(2))

        XCTAssertEqual(FundsFirestoreMapping.decodePriceBookEntry(FundsFirestoreMapping.encode(entry)), entry)
    }

    func test_firestoreDocumentID_hasNoSlashes() async {
        let id = FundsFirestoreMapping.documentID(forPriceBookKey: PriceBookEntry.key(for: "Salt / Pepper"))

        XCTAssertFalse(id.contains("/"))
        XCTAssertFalse(id.contains(" "))
    }

    // the two places prices come in both feed the book

    func test_receiptOrAddFormPrice_goesIntoThePriceBook() async {
        let environment = FundsEnvironment.inMemory(pantryRepository: InMemoryPantryRepository())
        let chicken = PantryItem(ingredient: Ingredient(name: "Chicken Breast"), quantity: 500, unit: .grams)

        FundsPurchasePriceRecorder(environment: environment).recordPurchasePrice(Decimal(string: "8.50")!, for: chicken)

        let entry = environment.priceBook.entry(forIngredientNamed: "chicken breast")
        XCTAssertEqual(entry?.unitCost, Money(Decimal(string: "0.017")!, .aud))
        XCTAssertEqual(entry?.unit, "g")
    }

    func test_priceTypedInMoneyInMyFridge_goesIntoThePriceBook() async throws {
        let pantry = InMemoryPantryRepository(seedItems: [
            PantryItem(ingredient: Ingredient(name: "Milk"), quantity: 2, unit: .liters)
        ])
        let environment = FundsEnvironment.inMemory(pantryRepository: pantry)
        let viewModel = MoneyInFridgeViewModel(environment: environment)
        await viewModel.reload()
        let milk = try XCTUnwrap(viewModel.items.first)

        _ = viewModel.savePrice(for: milk, totalPaidText: "4.50")

        XCTAssertEqual(environment.priceBook.entry(forIngredientNamed: "Milk")?.unitCost,
                       Money(Decimal(string: "2.25")!, .aud))
    }

    // once the milk is used up, a recipe can still price it from the book
    func test_priceOutlivesThePantryItem() async throws {
        let pantry = InMemoryPantryRepository(seedItems: [
            PantryItem(ingredient: Ingredient(name: "Milk"), quantity: 1, unit: .liters)
        ])
        let environment = FundsEnvironment.inMemory(pantryRepository: pantry)
        environment.budgetStore.saveBudget(makeWeeklyBudget(limit: 100))
        let viewModel = MoneyInFridgeViewModel(environment: environment)
        await viewModel.reload()
        _ = viewModel.savePrice(for: try XCTUnwrap(viewModel.items.first), totalPaidText: "2")

        let stored = try await pantry.fetchAll()
        let milkID = try XCTUnwrap(stored.first?.id)
        try await pantry.remove(id: milkID)
        await environment.reload()

        let recipe = Recipe(title: "Pancakes", summary: "", ingredients: [
            RecipeIngredient(ingredient: Ingredient(name: "Milk"), quantity: 250, unit: .milliliters, role: .essential)
        ], instructions: [])
        let estimate = environment.estimateRecipeCost.execute(recipe: recipe, now: TestDates.day(1))

        XCTAssertEqual(estimate.toBuy, Money(Decimal(string: "0.5")!, .aud))
    }
}
