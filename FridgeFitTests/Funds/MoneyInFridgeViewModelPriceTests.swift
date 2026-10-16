//
//  MoneyInFridgeViewModelPriceTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

// the price form takes "what you paid in total" and turns it into a per-unit cost
@MainActor
final class MoneyInFridgeViewModelPriceTests: XCTestCase {
    private func makeViewModel(_ items: [PantryItem]) async throws -> (MoneyInFridgeViewModel, FundsEnvironment) {
        let environment = FundsEnvironment.inMemory(pantryRepository: InMemoryPantryRepository(seedItems: items))
        environment.budgetStore.saveBudget(makeWeeklyBudget(limit: 100))
        let viewModel = MoneyInFridgeViewModel(environment: environment)
        await viewModel.reload()
        return (viewModel, environment)
    }

    func test_savePrice_turnsTotalIntoPerUnitCost() async throws {
        let (viewModel, environment) = try await makeViewModel([
            PantryItem(ingredient: Ingredient(name: "Eggs"), quantity: 6, unit: .pieces)
        ])
        let eggs = try XCTUnwrap(viewModel.items.first)

        let error = viewModel.savePrice(for: eggs, totalPaidText: "3")

        XCTAssertNil(error)
        XCTAssertEqual(environment.priceStore.info(for: eggs.id)?.unitCost, Money(Decimal(string: "0.5")!, .aud))
        XCTAssertEqual(viewModel.items.first?.lineValue, Money(3, .aud))
        XCTAssertEqual(viewModel.valuation?.totalValue, Money(3, .aud))
    }

    func test_pricedItem_expiringSoonInThePantry_countsAsAtRisk() async throws {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let (viewModel, _) = try await makeViewModel([
            PantryItem(ingredient: Ingredient(name: "Milk"), quantity: 1, unit: .liters, expiryDate: tomorrow)
        ])
        let milk = try XCTUnwrap(viewModel.items.first)

        _ = viewModel.savePrice(for: milk, totalPaidText: "4.50")

        XCTAssertEqual(viewModel.valuation?.atRiskValue, Money(Decimal(string: "4.5")!, .aud))
    }

    func test_savePrice_rejectsText() async throws {
        let (viewModel, environment) = try await makeViewModel([
            PantryItem(ingredient: Ingredient(name: "Rice"), quantity: 1, unit: .kilograms)
        ])
        let rice = try XCTUnwrap(viewModel.items.first)

        let error = viewModel.savePrice(for: rice, totalPaidText: "cheap")

        XCTAssertNotNil(error)
        XCTAssertNil(environment.priceStore.info(for: rice.id))
    }

    func test_savePrice_needsAQuantity_toWorkOutPerUnitCost() async throws {
        let (viewModel, _) = try await makeViewModel([
            PantryItem(ingredient: Ingredient(name: "Salt"), quantity: 0, unit: .grams)
        ])
        let salt = try XCTUnwrap(viewModel.items.first)

        XCTAssertNotNil(viewModel.savePrice(for: salt, totalPaidText: "2"))
    }

    func test_emptyPrice_isAllowed_andClearsIt() async throws {
        let (viewModel, environment) = try await makeViewModel([
            PantryItem(ingredient: Ingredient(name: "Bread"), quantity: 1, unit: .pieces)
        ])
        let bread = try XCTUnwrap(viewModel.items.first)
        _ = viewModel.savePrice(for: bread, totalPaidText: "4")

        XCTAssertNil(viewModel.savePrice(for: bread, totalPaidText: ""))

        XCTAssertNil(environment.priceStore.info(for: bread.id)?.unitCost)
        XCTAssertEqual(viewModel.valuation?.unvaluedItemCount, 1)
    }
}
