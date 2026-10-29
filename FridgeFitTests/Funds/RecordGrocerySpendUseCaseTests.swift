//
//  RecordGrocerySpendUseCaseTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class RecordGrocerySpendUseCaseTests: XCTestCase {

    // MARK: Happy path

    func test_recordGrocerySpend_addsSpend_onValidInput() async throws {
        let store = InMemoryBudgetStore(budget: makeWeeklyBudget(limit: 100))
        let sut = RecordGrocerySpendUseCase(budgetStore: store)

        let recorded = try await sut.execute(amount: aud(25),
                                             spentOn: TestDates.anchor,
                                             store: "Woolworths",
                                             now: TestDates.anchor)

        XCTAssertEqual(recorded.spend.amount, aud(25))
        XCTAssertEqual(recorded.outcome, .committed)
        XCTAssertEqual(store.allSpends().count, 1)
        XCTAssertEqual(store.allSpends().first?.store, "Woolworths")
    }

    // MARK: Failure cases

    func test_recordGrocerySpend_fails_whenAmountIsNotPositive() async {
        let store = InMemoryBudgetStore(budget: makeWeeklyBudget(limit: 100))
        let sut = RecordGrocerySpendUseCase(budgetStore: store)

        await assertThrowsAsync(try await sut.execute(amount: aud(0), now: TestDates.anchor)) { error in
            XCTAssertEqual(error as? RecordGrocerySpendUseCase.Failure, .amountNotPositive)
        }
        XCTAssertTrue(store.allSpends().isEmpty)
    }

    func test_recordGrocerySpend_fails_whenNoBudgetHasBeenSet() async {
        let store = InMemoryBudgetStore(budget: nil)
        let sut = RecordGrocerySpendUseCase(budgetStore: store)

        await assertThrowsAsync(try await sut.execute(amount: aud(20), now: TestDates.anchor)) { error in
            XCTAssertEqual(error as? RecordGrocerySpendUseCase.Failure, .noActiveBudgetPeriod)
        }
    }

    func test_recordGrocerySpend_fails_whenPurchaseIsDatedInFuture() async {
        let store = InMemoryBudgetStore(budget: makeWeeklyBudget(limit: 100))
        let sut = RecordGrocerySpendUseCase(budgetStore: store)

        await assertThrowsAsync(
            try await sut.execute(amount: aud(20),
                                  spentOn: TestDates.day(1),
                                  now: TestDates.anchor)
        ) { error in
            XCTAssertEqual(error as? RecordGrocerySpendUseCase.Failure, .purchaseDatedInFuture)
        }
    }

    func test_recordGrocerySpend_fails_whenCurrencyDiffersFromBudget() async {
        let store = InMemoryBudgetStore(budget: makeWeeklyBudget(limit: 100, currency: .aud))
        let sut = RecordGrocerySpendUseCase(budgetStore: store)

        await assertThrowsAsync(
            try await sut.execute(amount: Money(20, .usd), now: TestDates.anchor)
        ) { error in
            XCTAssertEqual(error as? RecordGrocerySpendUseCase.Failure,
                           .currencyMismatch(expected: .aud, got: .usd))
        }
    }

    // MARK: Business rule — going over budget is a warning, never a hard block

    func test_recordGrocerySpend_succeeds_evenWhenItExceedsRemainingBudget() async throws {
        let store = InMemoryBudgetStore(budget: makeWeeklyBudget(limit: 30))
        let sut = RecordGrocerySpendUseCase(budgetStore: store)

        // A $50 spend against a $30 budget must still be recorded — the user stays in control.
        let recorded = try await sut.execute(amount: aud(50), spentOn: TestDates.anchor, now: TestDates.anchor)

        XCTAssertEqual(recorded.spend.amount, aud(50))
        XCTAssertEqual(store.allSpends().count, 1)
    }

    // MARK: Storage failure propagation

    /// The regression this refactor exists for. The store's write used to
    /// return `Void`, so a refused write was indistinguishable from a
    /// successful one and the use case reported a recorded spend either way.
    func test_recordGrocerySpend_whenStoreRefusesTheWrite_throwsInsteadOfReportingSuccess() async {
        let store = FailingBudgetStore(budget: makeWeeklyBudget(limit: 100))
        let sut = RecordGrocerySpendUseCase(budgetStore: store)

        await assertThrowsAsync(
            try await sut.execute(amount: aud(25), spentOn: TestDates.anchor, now: TestDates.anchor),
            "A refused write must not be reported as a recorded spend"
        ) { error in
            XCTAssertTrue(error is FailingBudgetStore.WriteRefused, "Got \(error)")
        }

        XCTAssertTrue(store.allSpends().isEmpty, "Nothing may be left behind by a failed write")
        XCTAssertEqual(store.attemptedWrites, 1)
    }

    /// Retrying after a failure must record the spend once, not twice.
    func test_recordGrocerySpend_retryAfterFailure_recordsExactlyOneSpend() async throws {
        let store = FailingBudgetStore(budget: makeWeeklyBudget(limit: 100))
        let sut = RecordGrocerySpendUseCase(budgetStore: store)

        await assertThrowsAsync(
            try await sut.execute(amount: aud(25), spentOn: TestDates.anchor, now: TestDates.anchor)
        )

        store.shouldFail = false
        let recorded = try await sut.execute(amount: aud(25), spentOn: TestDates.anchor, now: TestDates.anchor)

        XCTAssertEqual(recorded.outcome, .committed)
        XCTAssertEqual(store.allSpends().count, 1, "A retry must not double-count the purchase")
        XCTAssertEqual(store.attemptedWrites, 2, "One write per attempt, no hidden retries")
    }

    /// A queued-but-unconfirmed write is a success with a caveat, not a
    /// failure: the spend is recorded and the outcome says so.
    func test_recordGrocerySpend_whenWriteIsOnlyQueued_reportsPendingSyncNotFailure() async throws {
        let store = PendingSyncBudgetStore(budget: makeWeeklyBudget(limit: 100))
        let sut = RecordGrocerySpendUseCase(budgetStore: store)

        let recorded = try await sut.execute(amount: aud(25), spentOn: TestDates.anchor, now: TestDates.anchor)

        XCTAssertEqual(recorded.outcome, .pendingSync)
        XCTAssertEqual(store.allSpends().count, 1, "A queued write is still applied locally")
        XCTAssertNotNil(FundsWriteOutcome.pendingSync.statusDescription)
        XCTAssertNil(FundsWriteOutcome.committed.statusDescription, "A confirmed write needs no notice")
    }
}

/// A `BudgetStore` that applies writes locally and reports them as queued,
/// the way Firestore behaves on an offline device.
@MainActor
final class PendingSyncBudgetStore: BudgetStore {
    private let inner: InMemoryBudgetStore

    init(budget: FoodBudget? = nil) {
        inner = InMemoryBudgetStore(budget: budget)
    }

    func activeBudget() -> FoodBudget? { inner.activeBudget() }

    @discardableResult
    func saveBudget(_ budget: FoodBudget) async throws -> FundsWriteOutcome {
        _ = try await inner.saveBudget(budget)
        return .pendingSync
    }

    func allSpends() -> [GrocerySpend] { inner.allSpends() }

    @discardableResult
    func addSpend(_ spend: GrocerySpend) async throws -> FundsWriteOutcome {
        _ = try await inner.addSpend(spend)
        return .pendingSync
    }

    func allWasteCosts() -> [WastedFoodCost] { inner.allWasteCosts() }

    @discardableResult
    func addWasteCost(_ cost: WastedFoodCost) async throws -> FundsWriteOutcome {
        _ = try await inner.addWasteCost(cost)
        return .pendingSync
    }

    func wasteAlreadyRecorded(for itemID: PantryItemID, on day: Date) -> Bool {
        inner.wasteAlreadyRecorded(for: itemID, on: day)
    }
}
