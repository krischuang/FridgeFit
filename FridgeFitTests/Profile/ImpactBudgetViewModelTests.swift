//
//  ImpactBudgetViewModelTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// The loading and writing half of Profile → Impact & Budget.
@MainActor
final class ImpactBudgetViewModelTests: XCTestCase {

    // MARK: - Without FridgeFunds wired in

    func test_withoutFunds_theMoneyCardsStayUnavailableButTheActivityLogStillReads() async {
        let viewModel = ImpactBudgetViewModel(funds: nil)
        let events = [
            InventoryEvent(pantryItemID: UUID(), itemName: "Spinach", kind: .finished),
            InventoryEvent(pantryItemID: UUID(), itemName: "Milk", kind: .discarded),
        ]

        await viewModel.refresh(events: events)

        XCTAssertFalse(viewModel.isFundsAvailable)
        XCTAssertNil(viewModel.summary.budget)
        XCTAssertNil(viewModel.summary.valuation)
        XCTAssertNil(viewModel.summary.atRiskValue)
        XCTAssertEqual(viewModel.summary.kitchen.finishedThisMonth, 1)
        XCTAssertEqual(viewModel.summary.kitchen.pantryEfficiencyPercent ?? 0, 50, accuracy: 0.0001)
    }

    // MARK: - Reading the real pantry

    func test_refresh_readsThePantryThroughTheSharedRepository() async {
        let spinach = PantryItem(
            ingredient: Ingredient(name: "Baby Spinach", category: .produce),
            quantity: 1,
            unit: .pieces,
            expiryDate: Calendar.current.date(byAdding: .day, value: 1, to: .now)
        )
        let pantry = InMemoryPantryRepository(seedItems: [spinach])
        let funds = FundsEnvironment.inMemory(pantryRepository: pantry)
        let viewModel = ImpactBudgetViewModel(funds: funds)

        await viewModel.refresh(events: [])

        XCTAssertEqual(viewModel.summary.atRiskIngredients.map(\.name), ["Baby Spinach"])
        XCTAssertNil(viewModel.summary.atRiskValue, "No price recorded for it yet.")
        XCTAssertEqual(viewModel.summary.atRiskIngredients.first?.category, .produce)
    }

    // MARK: - Writes

    func test_savingABudget_makesTheProgressBarReal() async {
        let funds = FundsEnvironment.inMemory(pantryRepository: InMemoryPantryRepository())
        let viewModel = ImpactBudgetViewModel(funds: funds)
        await viewModel.refresh(events: [])
        XCTAssertNil(viewModel.summary.budget)

        viewModel.saveBudget(limit: 320, currency: .aud, cadence: .fortnightly, startDate: .now, events: [])

        XCTAssertEqual(viewModel.summary.budget?.budget.limit, Money(320, .aud))
        XCTAssertEqual(viewModel.summary.budget?.totalSpent, Money(0, .aud))
        XCTAssertNil(viewModel.actionError)
    }

    func test_aBudgetOfZeroIsRejected() async {
        let funds = FundsEnvironment.inMemory(pantryRepository: InMemoryPantryRepository())
        let viewModel = ImpactBudgetViewModel(funds: funds)

        viewModel.saveBudget(limit: 0, currency: .aud, cadence: .weekly, startDate: .now, events: [])

        XCTAssertNotNil(viewModel.actionError)
        XCTAssertNil(viewModel.summary.budget)
    }

    func test_loggingASpend_movesTheProgressBar_andDoesNotBlockGoingOver() async {
        let funds = FundsEnvironment.inMemory(pantryRepository: InMemoryPantryRepository())
        let viewModel = ImpactBudgetViewModel(funds: funds)
        viewModel.saveBudget(limit: 100, currency: .aud, cadence: .weekly, startDate: .now, events: [])

        viewModel.logSpend(amount: 130, spentOn: .now, store: "Woolworths", events: [])

        XCTAssertNil(viewModel.actionError, "Going over budget is reported, never refused.")
        XCTAssertEqual(viewModel.summary.budget?.totalSpent, Money(130, .aud))
        XCTAssertTrue(viewModel.summary.budget?.hasOverspent ?? false)
    }

    func test_loggingASpendWithNoBudget_surfacesTheReason() async {
        let funds = FundsEnvironment.inMemory(pantryRepository: InMemoryPantryRepository())
        let viewModel = ImpactBudgetViewModel(funds: funds)

        viewModel.logSpend(amount: 20, spentOn: .now, store: nil, events: [])

        XCTAssertEqual(viewModel.actionError, RecordGrocerySpendUseCase.Failure.noActiveBudgetPeriod.errorDescription)
    }

    func test_savingAPrice_valuesTheItem_andRemembersItInThePriceBook() async throws {
        let spinach = PantryItem(
            ingredient: Ingredient(name: "Baby Spinach", category: .produce),
            quantity: 2,
            unit: .pieces,
            expiryDate: Calendar.current.date(byAdding: .day, value: 1, to: .now)
        )
        let funds = FundsEnvironment.inMemory(pantryRepository: InMemoryPantryRepository(seedItems: [spinach]))
        let viewModel = ImpactBudgetViewModel(funds: funds)
        await viewModel.refresh(events: [])
        let item = try XCTUnwrap(viewModel.summary.atRiskIngredients.first)

        viewModel.savePrice(for: item, unitCost: Decimal(string: "3.80")!, unit: item.unit, events: [])

        XCTAssertEqual(viewModel.summary.atRiskValue, Money(Decimal(string: "7.60")!, .aud), "Two bags at $3.80 each.")
        XCTAssertEqual(
            viewModel.suggestedUnitCost(forIngredientNamed: "baby spinach"),
            Money(Decimal(string: "3.80")!, .aud)
        )
    }

    func test_aPriceOfZeroOrLessIsRejected() async throws {
        let spinach = PantryItem(
            ingredient: Ingredient(name: "Baby Spinach", category: .produce),
            quantity: 1,
            unit: .pieces,
            expiryDate: Calendar.current.date(byAdding: .day, value: 1, to: .now)
        )
        let funds = FundsEnvironment.inMemory(pantryRepository: InMemoryPantryRepository(seedItems: [spinach]))
        let viewModel = ImpactBudgetViewModel(funds: funds)
        await viewModel.refresh(events: [])
        let item = try XCTUnwrap(viewModel.summary.atRiskIngredients.first)

        viewModel.savePrice(for: item, unitCost: 0, unit: item.unit, events: [])

        XCTAssertNotNil(viewModel.actionError)
        XCTAssertNil(viewModel.summary.atRiskValue)
    }

    /// Saving a price must not touch the pantry - FridgeFunds only reads it.
    func test_savingAPrice_doesNotWriteToThePantry() async throws {
        let spinach = PantryItem(
            ingredient: Ingredient(name: "Baby Spinach", category: .produce),
            quantity: 1,
            unit: .pieces,
            expiryDate: Calendar.current.date(byAdding: .day, value: 1, to: .now)
        )
        let repository = InMemoryPantryRepository(seedItems: [spinach])
        let viewModel = ImpactBudgetViewModel(funds: .inMemory(pantryRepository: repository))
        await viewModel.refresh(events: [])
        let item = try XCTUnwrap(viewModel.summary.atRiskIngredients.first)

        viewModel.savePrice(for: item, unitCost: 2, unit: item.unit, events: [])

        let stored = try await repository.fetchAll()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first, spinach)
    }

    // MARK: - Input parsing

    func test_decimalInput_readsMoneyWithoutGoingThroughADouble() {
        XCTAssertEqual(DecimalInput.parse("4.50"), Decimal(string: "4.50"))
        XCTAssertEqual(DecimalInput.parse(" 320 "), 320)
        XCTAssertNil(DecimalInput.parse(""))
        XCTAssertNil(DecimalInput.parse("   "))
        XCTAssertNil(DecimalInput.parse("abc"))
    }
}
