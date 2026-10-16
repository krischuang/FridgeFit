//
//  RecordGrocerySpendUseCaseTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class RecordGrocerySpendUseCaseTests: XCTestCase {

    // MARK: Happy path

    func test_recordGrocerySpend_addsSpend_onValidInput() throws {
        let store = InMemoryBudgetStore(budget: makeWeeklyBudget(limit: 100))
        let sut = RecordGrocerySpendUseCase(budgetStore: store)

        let spend = try sut.execute(amount: aud(25),
                                    spentOn: TestDates.anchor,
                                    store: "Woolworths",
                                    now: TestDates.anchor)

        XCTAssertEqual(spend.amount, aud(25))
        XCTAssertEqual(store.allSpends().count, 1)
        XCTAssertEqual(store.allSpends().first?.store, "Woolworths")
    }

    // MARK: Failure cases

    func test_recordGrocerySpend_fails_whenAmountIsNotPositive() {
        let store = InMemoryBudgetStore(budget: makeWeeklyBudget(limit: 100))
        let sut = RecordGrocerySpendUseCase(budgetStore: store)

        XCTAssertThrowsError(try sut.execute(amount: aud(0), now: TestDates.anchor)) { error in
            XCTAssertEqual(error as? RecordGrocerySpendUseCase.Failure, .amountNotPositive)
        }
        XCTAssertTrue(store.allSpends().isEmpty)
    }

    func test_recordGrocerySpend_fails_whenNoBudgetHasBeenSet() {
        let store = InMemoryBudgetStore(budget: nil)
        let sut = RecordGrocerySpendUseCase(budgetStore: store)

        XCTAssertThrowsError(try sut.execute(amount: aud(20), now: TestDates.anchor)) { error in
            XCTAssertEqual(error as? RecordGrocerySpendUseCase.Failure, .noActiveBudgetPeriod)
        }
    }

    func test_recordGrocerySpend_fails_whenPurchaseIsDatedInFuture() {
        let store = InMemoryBudgetStore(budget: makeWeeklyBudget(limit: 100))
        let sut = RecordGrocerySpendUseCase(budgetStore: store)

        XCTAssertThrowsError(
            try sut.execute(amount: aud(20),
                            spentOn: TestDates.day(1),
                            now: TestDates.anchor)
        ) { error in
            XCTAssertEqual(error as? RecordGrocerySpendUseCase.Failure, .purchaseDatedInFuture)
        }
    }

    func test_recordGrocerySpend_fails_whenCurrencyDiffersFromBudget() {
        let store = InMemoryBudgetStore(budget: makeWeeklyBudget(limit: 100, currency: .aud))
        let sut = RecordGrocerySpendUseCase(budgetStore: store)

        XCTAssertThrowsError(
            try sut.execute(amount: Money(20, .usd), now: TestDates.anchor)
        ) { error in
            XCTAssertEqual(error as? RecordGrocerySpendUseCase.Failure,
                           .currencyMismatch(expected: .aud, got: .usd))
        }
    }

    // MARK: Business rule — going over budget is a warning, never a hard block

    func test_recordGrocerySpend_succeeds_evenWhenItExceedsRemainingBudget() throws {
        let store = InMemoryBudgetStore(budget: makeWeeklyBudget(limit: 30))
        let sut = RecordGrocerySpendUseCase(budgetStore: store)

        // A $50 spend against a $30 budget must still be recorded — the user stays in control.
        let spend = try sut.execute(amount: aud(50), spentOn: TestDates.anchor, now: TestDates.anchor)

        XCTAssertEqual(spend.amount, aud(50))
        XCTAssertEqual(store.allSpends().count, 1)
    }
}
