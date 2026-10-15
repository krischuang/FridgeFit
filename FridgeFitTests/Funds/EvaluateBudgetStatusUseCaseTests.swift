import XCTest
@testable import FridgeFit

final class EvaluateBudgetStatusUseCaseTests: XCTestCase {

    // MARK: Happy path

    func test_evaluateStatus_reportsRemainingAndTodaysAllowance_afterSpends() throws {
        // $140 weekly budget → $20/day. One $30 spend on day 0; evaluated on day 2.
        let budget = makeWeeklyBudget(limit: 140)
        let spend = GrocerySpend(amount: aud(30), spentOn: TestDates.day(0))
        let store = InMemoryBudgetStore(budget: budget, spends: [spend])
        let sut = EvaluateBudgetStatusUseCase(budgetStore: store)

        let status = try sut.execute(now: TestDates.day(2))

        XCTAssertEqual(status.totalSpent, aud(30))
        XCTAssertEqual(status.remaining, aud(110))
        XCTAssertEqual(status.dailyAllowance, aud(20))
        XCTAssertEqual(status.todayRemaining, aud(20))   // nothing spent on day 2
        XCTAssertEqual(status.daysElapsed, 3)            // day 0 counts as day 1
        XCTAssertFalse(status.hasOverspent)
    }

    // MARK: Boundary — today's allowance never goes negative

    func test_evaluateStatus_clampsTodaysAllowanceToZero_whenTodaysSpendExceedsIt() throws {
        // $140 weekly → $20/day, but $30 spent today.
        let budget = makeWeeklyBudget(limit: 140)
        let spend = GrocerySpend(amount: aud(30), spentOn: TestDates.anchor)
        let store = InMemoryBudgetStore(budget: budget, spends: [spend])
        let sut = EvaluateBudgetStatusUseCase(budgetStore: store)

        let status = try sut.execute(now: TestDates.anchor)

        XCTAssertEqual(status.todayRemaining, aud(0))
    }

    // MARK: Error state — already overspent

    func test_evaluateStatus_flagsOverspent_whenSpendsExceedTheLimit() throws {
        let budget = makeWeeklyBudget(limit: 100)
        let spends = [
            GrocerySpend(amount: aud(70), spentOn: TestDates.day(0)),
            GrocerySpend(amount: aud(50), spentOn: TestDates.day(1))
        ]
        let store = InMemoryBudgetStore(budget: budget, spends: spends)
        let sut = EvaluateBudgetStatusUseCase(budgetStore: store)

        let status = try sut.execute(now: TestDates.day(2))

        XCTAssertEqual(status.remaining, aud(-20))
        XCTAssertTrue(status.hasOverspent)
    }

    // MARK: Forecast — on track to overspend even while still in the black

    func test_evaluateStatus_projectsOverspend_atCurrentPace() throws {
        // $70 weekly. $30 spent across the first 2 days → $15/day pace → projected $105.
        let budget = makeWeeklyBudget(limit: 70)
        let spends = [
            GrocerySpend(amount: aud(15), spentOn: TestDates.day(0)),
            GrocerySpend(amount: aud(15), spentOn: TestDates.day(1))
        ]
        let store = InMemoryBudgetStore(budget: budget, spends: spends)
        let sut = EvaluateBudgetStatusUseCase(budgetStore: store)

        let status = try sut.execute(now: TestDates.day(1))   // daysElapsed = 2

        XCTAssertEqual(status.projectedEndBalance, aud(-35))  // 70 − (15 × 7)
        XCTAssertTrue(status.isProjectedToOverspend)
        XCTAssertFalse(status.hasOverspent)                   // not over *yet*
    }

    // MARK: Failure case

    func test_evaluateStatus_fails_whenNoBudgetHasBeenSet() {
        let store = InMemoryBudgetStore(budget: nil)
        let sut = EvaluateBudgetStatusUseCase(budgetStore: store)

        XCTAssertThrowsError(try sut.execute(now: TestDates.anchor)) { error in
            XCTAssertEqual(error as? EvaluateBudgetStatusUseCase.Failure, .noActiveBudgetPeriod)
        }
    }
}
