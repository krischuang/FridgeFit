import XCTest
@testable import FridgeFit

final class RecordDiscardedItemCostUseCaseTests: XCTestCase {

    private let itemID = PantryItemID("test-item")

    // MARK: Happy path

    func test_recordDiscardedCost_valuesLossFromCostBasis_onValidInput() throws {
        let pantry = makePantry(unitCost: aud(0.50), quantity: 10)
        let store = InMemoryBudgetStore()
        let sut = RecordDiscardedItemCostUseCase(pantry: pantry, budgetStore: store)

        let cost = try sut.execute(itemID: itemID,
                                   quantityDiscarded: 4,
                                   reason: .expired,
                                   discardedOn: TestDates.anchor)

        // 4 units × $0.50 = $2.00
        XCTAssertEqual(cost.lostAmount, aud(2))
        XCTAssertEqual(store.allWasteCosts().count, 1)
    }

    // MARK: Boundary / failure cases

    func test_recordDiscardedCost_fails_whenQuantityExceedsWhatIsOnHand() {
        let pantry = makePantry(unitCost: aud(0.50), quantity: 10, unit: "each")
        let sut = RecordDiscardedItemCostUseCase(pantry: pantry, budgetStore: InMemoryBudgetStore())

        XCTAssertThrowsError(
            try sut.execute(itemID: itemID, quantityDiscarded: 20, reason: .spoiled)
        ) { error in
            XCTAssertEqual(error as? RecordDiscardedItemCostUseCase.Failure,
                           .quantityExceedsOnHand(available: 10, unit: "each"))
        }
    }

    func test_recordDiscardedCost_fails_whenItemHasNoRecordedPrice() {
        let pantry = makePantry(unitCost: nil, quantity: 5, name: "Leftover sauce")
        let sut = RecordDiscardedItemCostUseCase(pantry: pantry, budgetStore: InMemoryBudgetStore())

        XCTAssertThrowsError(
            try sut.execute(itemID: itemID, quantityDiscarded: 1, reason: .spoiled)
        ) { error in
            XCTAssertEqual(error as? RecordDiscardedItemCostUseCase.Failure,
                           .itemHasNoRecordedCost(itemName: "Leftover sauce"))
        }
    }

    func test_recordDiscardedCost_fails_whenItemIsNotInThePantry() {
        let pantry = makePantry(unitCost: aud(0.50))
        let sut = RecordDiscardedItemCostUseCase(pantry: pantry, budgetStore: InMemoryBudgetStore())

        XCTAssertThrowsError(
            try sut.execute(itemID: PantryItemID("not-in-fridge"),
                            quantityDiscarded: 1, reason: .expired)
        ) { error in
            XCTAssertEqual(error as? RecordDiscardedItemCostUseCase.Failure, .itemNotInPantry)
        }
    }

    // MARK: Business rule — a discard is counted at most once per day

    func test_recordDiscardedCost_fails_whenSameItemAlreadyWastedToday() {
        let pantry = makePantry(unitCost: aud(0.50), quantity: 10, name: "Baby spinach")
        let alreadyWasted = WastedFoodCost(pantryItemID: itemID,
                                           quantityDiscarded: 2,
                                           lostAmount: aud(1),
                                           discardedOn: TestDates.anchor,
                                           reason: .expired)
        let store = InMemoryBudgetStore(wasteCosts: [alreadyWasted])
        let sut = RecordDiscardedItemCostUseCase(pantry: pantry, budgetStore: store)

        XCTAssertThrowsError(
            try sut.execute(itemID: itemID, quantityDiscarded: 3,
                            reason: .expired, discardedOn: TestDates.anchor)
        ) { error in
            XCTAssertEqual(error as? RecordDiscardedItemCostUseCase.Failure,
                           .wasteAlreadyRecorded(itemName: "Baby spinach"))
        }
        // The waste total was not inflated by the rejected second record.
        XCTAssertEqual(store.allWasteCosts().count, 1)
    }
}
