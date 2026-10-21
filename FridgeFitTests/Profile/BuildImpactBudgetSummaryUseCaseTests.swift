//
//  BuildImpactBudgetSummaryUseCaseTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// The arithmetic behind Profile → Impact & Budget.
///
/// Every case here pins one of the screen's claims to a recorded fact, or
/// pins an *absence* of data to an absence of a number.
@MainActor
final class BuildImpactBudgetSummaryUseCaseTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private lazy var now = day(2026, 10, 19)

    // MARK: - Empty states

    func test_emptyFridgeAndNoBudget_reportsNothingRatherThanZeroes() {
        let summary = makeSummary(pantry: [], budget: nil, events: [])

        XCTAssertNil(summary.budget, "No budget set means no budget status at all.")
        XCTAssertNil(summary.atRiskValue, "An unpriced fridge is not a fridge worth $0.00.")
        XCTAssertTrue(summary.atRiskIngredients.isEmpty)
        XCTAssertFalse(summary.hasAtRiskIngredients, "The primary action must be disabled with nothing to plan.")
        XCTAssertNil(summary.kitchen.pantryEfficiencyPercent)
        XCTAssertNil(summary.kitchen.zeroWasteStreakWeeks)
    }

    func test_itemsWithNoExpiryDate_areNeverAtRisk() {
        let summary = makeSummary(
            pantry: [snapshot(name: "Rice", quantity: 2, unit: "kg", expiresInDays: nil, unitCost: aud(3))],
            budget: nil,
            events: []
        )

        XCTAssertTrue(summary.atRiskIngredients.isEmpty, "An undated item is untracked, not urgent.")
        XCTAssertEqual(summary.valuation?.atRiskItemCount, 0)
    }

    // MARK: - Value at risk

    func test_valueAtRisk_sumsOnlyPricedItemsInsideTheWindow_andCountsTheRest() {
        let summary = makeSummary(
            pantry: [
                snapshot(name: "Baby Spinach", quantity: 1, unit: "bag", expiresInDays: 1, unitCost: aud(Decimal(string: "3.80")!)),
                snapshot(name: "Brown Mushrooms", quantity: 1, unit: "tub", expiresInDays: 2, unitCost: aud(Decimal(string: "4.50")!)),
                snapshot(name: "Leftover Sauce", quantity: 1, unit: "jar", expiresInDays: 2, unitCost: nil),
                snapshot(name: "Rice", quantity: 2, unit: "kg", expiresInDays: 180, unitCost: aud(3)),
            ],
            budget: nil,
            events: []
        )

        XCTAssertEqual(summary.atRiskValue, aud(Decimal(string: "8.30")!))
        XCTAssertEqual(summary.valuation?.atRiskItemCount, 2)
        XCTAssertEqual(summary.valuation?.atRiskUnvaluedCount, 1, "The unpriced jar is counted, not dropped.")
        XCTAssertEqual(summary.atRiskIngredients.map(\.name), ["Baby Spinach", "Brown Mushrooms", "Leftover Sauce"])
    }

    func test_atRiskList_includesExpiredItemsFirst() {
        let summary = makeSummary(
            pantry: [
                snapshot(name: "Fresh", quantity: 1, unit: "bag", expiresInDays: 3, unitCost: aud(1)),
                snapshot(name: "Gone Off", quantity: 1, unit: "tub", expiresInDays: -2, unitCost: aud(1)),
            ],
            budget: nil,
            events: []
        )

        XCTAssertEqual(summary.atRiskIngredients.map(\.name), ["Gone Off", "Fresh"])
        XCTAssertEqual(summary.atRiskIngredients.first?.expiryText, "Expired")
        XCTAssertEqual(summary.atRiskIngredients.first?.urgency, .expired)
    }

    func test_atRiskValue_isUnavailableWhenNothingExpiringHasAPrice() {
        let summary = makeSummary(
            pantry: [snapshot(name: "Leftover Sauce", quantity: 1, unit: "jar", expiresInDays: 1, unitCost: nil)],
            budget: nil,
            events: []
        )

        XCTAssertNil(summary.atRiskValue, "One unpriced item at risk is not $0.00 at risk.")
        XCTAssertTrue(summary.hasAtRiskIngredients, "It is still listed, and still worth cooking.")
    }

    func test_itemWithAZeroPrice_isValuedAtZeroRatherThanTreatedAsUnpriced() {
        let summary = makeSummary(
            pantry: [snapshot(name: "Giveaway Bread", quantity: 1, unit: "loaf", expiresInDays: 1, unitCost: aud(0))],
            budget: nil,
            events: []
        )

        XCTAssertEqual(summary.valuation?.atRiskItemCount, 1)
        XCTAssertEqual(summary.valuation?.atRiskUnvaluedCount, 0)
        XCTAssertEqual(summary.atRiskValue, aud(0))
    }

    func test_largeAmounts_keepTheirPrecisionThroughDecimal() {
        let summary = makeSummary(
            pantry: [snapshot(name: "Wagyu", quantity: 3, unit: "kg", expiresInDays: 1, unitCost: aud(Decimal(string: "1234567.89")!))],
            budget: nil,
            events: []
        )

        XCTAssertEqual(summary.atRiskValue, aud(Decimal(string: "3703703.67")!))
    }

    // MARK: - Budget

    func test_budgetProgress_readsTheActiveBudgetAndItsSpends() {
        let budget = FoodBudget(limit: aud(320), cadence: .fortnightly, startDate: day(2026, 10, 15))
        let store = InMemoryBudgetStore(budget: budget, spends: [
            GrocerySpend(amount: aud(Decimal(string: "150.00")!), spentOn: day(2026, 10, 15)),
            GrocerySpend(amount: aud(Decimal(string: "64.50")!), spentOn: day(2026, 10, 18)),
            GrocerySpend(amount: aud(100), spentOn: day(2026, 9, 1)), // before the period
        ])

        let summary = makeSummary(pantry: [], budgetStore: store, events: [])

        XCTAssertEqual(summary.budget?.totalSpent, aud(Decimal(string: "214.50")!))
        XCTAssertEqual(summary.budget?.remaining, aud(Decimal(string: "105.50")!))
        XCTAssertFalse(summary.budget?.hasOverspent ?? true)
    }

    func test_overspentBudget_reportsANegativeRemainder() {
        let budget = FoodBudget(limit: aud(100), cadence: .weekly, startDate: day(2026, 10, 15))
        let store = InMemoryBudgetStore(budget: budget, spends: [
            GrocerySpend(amount: aud(130), spentOn: day(2026, 10, 18))
        ])

        let summary = makeSummary(pantry: [], budgetStore: store, events: [])

        XCTAssertTrue(summary.budget?.hasOverspent ?? false)
        XCTAssertEqual(summary.budget?.remaining, aud(-30))
    }

    func test_totalsUseTheBudgetsCurrency_notTheLocales() {
        let budget = FoodBudget(limit: Money(200, .gbp), cadence: .weekly, startDate: day(2026, 10, 15))
        let summary = makeSummary(
            pantry: [snapshot(name: "Cheddar", quantity: 1, unit: "kg", expiresInDays: 1, unitCost: Money(10, .gbp))],
            budgetStore: InMemoryBudgetStore(budget: budget),
            events: [],
            fallbackCurrency: .usd
        )

        XCTAssertEqual(summary.currency, .gbp)
        XCTAssertEqual(summary.atRiskValue, Money(10, .gbp))
    }

    // MARK: - Valued waste

    func test_wasteReading_separatesValuedWasteFromDiscardsThatHaveNoPrice() {
        let itemID = PantryItemID("binned")
        let store = InMemoryBudgetStore(
            budget: FoodBudget(limit: aud(100), cadence: .weekly, startDate: day(2026, 10, 15)),
            wasteCosts: [
                WastedFoodCost(pantryItemID: itemID, quantityDiscarded: 1, lostAmount: aud(4), discardedOn: day(2026, 10, 10), reason: .expired),
                WastedFoodCost(pantryItemID: itemID, quantityDiscarded: 1, lostAmount: aud(6), discardedOn: day(2026, 9, 10), reason: .expired),
            ]
        )
        let events = (0..<3).map {
            InventoryEvent(pantryItemID: UUID(), itemName: "Item \($0)", kind: .discarded, date: day(2026, 10, 11))
        }

        let summary = makeSummary(pantry: [], budgetStore: store, events: events)

        XCTAssertEqual(summary.waste.thisMonth, aud(4))
        XCTAssertEqual(summary.waste.lastMonth, aud(6))
        XCTAssertEqual(summary.waste.recordCountThisMonth, 1)
        XCTAssertEqual(
            summary.waste.unvaluedDiscardsThisMonth,
            2,
            "Three discards were logged and one was valued; the money and the count are never added together."
        )
    }

    func test_monthOverMonthChange_isUnavailableWhenLastMonthWasZero() {
        let store = InMemoryBudgetStore(wasteCosts: [
            WastedFoodCost(pantryItemID: PantryItemID("x"), quantityDiscarded: 1, lostAmount: aud(4), discardedOn: day(2026, 10, 10), reason: .expired)
        ])

        let summary = makeSummary(pantry: [], budgetStore: store, events: [])

        XCTAssertNil(summary.waste.monthOverMonthPercent, "There is no percentage change from nothing.")
    }

    // MARK: - Formatting

    func test_quantityText_dropsTheDecimalPointForWholeAmounts() {
        XCTAssertEqual(BuildImpactBudgetSummaryUseCase.quantityText(1, unit: "bag"), "1 bag")
        XCTAssertEqual(BuildImpactBudgetSummaryUseCase.quantityText(200, unit: "g"), "200 g")
        XCTAssertEqual(BuildImpactBudgetSummaryUseCase.quantityText(0.6, unit: "kg"), "0.6 kg")
        XCTAssertEqual(BuildImpactBudgetSummaryUseCase.quantityText(2, unit: ""), "2")
    }

    // MARK: - Helpers

    private func makeSummary(
        pantry: [PantryItemSnapshot],
        budget: FoodBudget? = nil,
        events: [InventoryEvent],
        fallbackCurrency: Currency = .aud
    ) -> ImpactBudgetSummary {
        makeSummary(
            pantry: pantry,
            budgetStore: InMemoryBudgetStore(budget: budget),
            events: events,
            fallbackCurrency: fallbackCurrency
        )
    }

    private func makeSummary(
        pantry: [PantryItemSnapshot],
        budgetStore: BudgetStore,
        events: [InventoryEvent],
        fallbackCurrency: Currency = .aud
    ) -> ImpactBudgetSummary {
        let reading = InMemoryPantryReading(items: pantry)
        let useCase = BuildImpactBudgetSummaryUseCase(
            valueFridge: ValueFridgeUseCase(pantry: reading),
            evaluateBudget: EvaluateBudgetStatusUseCase(budgetStore: budgetStore),
            budgetStore: budgetStore
        )
        return useCase.execute(events: events, currency: fallbackCurrency, now: now, calendar: calendar)
    }

    private func snapshot(
        name: String,
        quantity: Double,
        unit: String,
        expiresInDays: Int?,
        unitCost: Money?
    ) -> PantryItemSnapshot {
        PantryItemSnapshot(
            id: PantryItemID(name),
            name: name,
            quantity: quantity,
            unit: unit,
            expiryDate: expiresInDays.map { calendar.date(byAdding: .day, value: $0, to: now)! },
            unitCost: unitCost,
            category: .produce
        )
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 12))!
    }
}
