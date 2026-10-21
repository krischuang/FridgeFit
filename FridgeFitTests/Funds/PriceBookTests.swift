//
//  PriceBookTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

// The price book: every recorded price also lands here under the ingredient's
// name, so it survives the pantry item being used up.
//
// Adapted from `feature/fridge-funds`. The SwiftData cases from that branch
// are not carried over - this branch has no SwiftData persistence layer, so
// there is no `SwiftDataPriceBookStore` to exercise.
@MainActor
final class PriceBookTests: XCTestCase {

    func test_inMemory_latestPriceWins_andNameMatchIgnoresCase() {
        let book = InMemoryPriceBookStore()
        book.record(PriceBookEntry(displayName: "Milk", unitCost: aud(2), unit: "L"))
        book.record(PriceBookEntry(displayName: "milk ", unitCost: Money(Decimal(string: "2.25")!, .aud), unit: "L"))

        XCTAssertEqual(book.entry(forIngredientNamed: "MILK")?.unitCost, Money(Decimal(string: "2.25")!, .aud))
    }

    func test_firestoreMapping_roundTrips() {
        let entry = PriceBookEntry(
            displayName: "Chicken Breast",
            unitCost: Money(Decimal(string: "0.017")!, .aud),
            unit: "g",
            recordedOn: TestDates.day(2)
        )

        XCTAssertEqual(FundsFirestoreMapping.decodePriceBookEntry(FundsFirestoreMapping.encode(entry)), entry)
    }

    func test_firestoreDocumentID_hasNoSlashes() {
        let id = FundsFirestoreMapping.documentID(forPriceBookKey: PriceBookEntry.key(for: "Salt / Pepper"))

        XCTAssertFalse(id.contains("/"))
        XCTAssertFalse(id.contains(" "))
    }

    /// Once the milk is used up its pantry item is gone, but the price book
    /// still knows what milk cost - which is the whole reason it is keyed by
    /// name rather than by pantry item id.
    func test_recordedPriceOutlivesThePantryItem() async throws {
        let milk = PantryItem(ingredient: Ingredient(name: "Milk", category: .dairy), quantity: 2, unit: .liters)
        let pantry = InMemoryPantryRepository(seedItems: [milk])
        let environment = FundsEnvironment.inMemory(pantryRepository: pantry)
        await environment.reload()

        environment.rememberPrice(of: "Milk", unit: "L", unitCost: Money(Decimal(string: "2.25")!, .aud))

        try await pantry.remove(id: milk.id)
        await environment.reload()

        XCTAssertTrue(environment.pantry.allItems().isEmpty)
        XCTAssertEqual(
            environment.priceBook.entry(forIngredientNamed: "milk")?.unitCost,
            Money(Decimal(string: "2.25")!, .aud)
        )
    }
}
