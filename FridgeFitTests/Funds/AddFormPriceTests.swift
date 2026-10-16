//
//  AddFormPriceTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

// price + expiry typed into the Pantry "Add to Pantry" form -> Budget tab
@MainActor
final class AddFormPriceTests: XCTestCase {

    private func setup() -> (PantryViewModel, FundsEnvironment) {
        let pantry = InMemoryPantryRepository()
        let environment = FundsEnvironment.inMemory(pantryRepository: pantry)
        environment.budgetStore.saveBudget(makeWeeklyBudget(limit: 100))
        let viewModel = PantryViewModel(pantryRepository: pantry,
                                        priceRecorder: FundsPurchasePriceRecorder(environment: environment))
        return (viewModel, environment)
    }

    func test_addingWithAPrice_showsUpAsMoneyInTheFridge() async throws {
        let (pantryViewModel, environment) = setup()

        await pantryViewModel.addItem(name: "Eggs", quantity: 12, unit: .pieces, category: .dairy, pricePaid: 6)

        let money = MoneyInFridgeViewModel(environment: environment)
        await money.reload()
        XCTAssertEqual(money.valuation?.totalValue, Money(6, .aud))
        let eggs = try XCTUnwrap(pantryViewModel.items.first)
        XCTAssertEqual(environment.priceStore.info(for: FridgeFitPantryReading.id(for: eggs))?.unitCost,
                       Money(Decimal(string: "0.5")!, .aud))
    }

    func test_addingWithPriceAndExpiry_priceToBudget_expiryOntoThePantryItem() async throws {
        let (pantryViewModel, environment) = setup()

        await pantryViewModel.addItem(name: "Milk", quantity: 1, unit: .liters, category: .dairy,
                                      pricePaid: Decimal(string: "4.50"), expiryDate: TestDates.day(3))

        let milk = try XCTUnwrap(pantryViewModel.items.first)
        // expiry is a pantry field now, same one the Kitchen tab edits
        XCTAssertEqual(milk.expiryDate, TestDates.day(3))
        XCTAssertEqual(environment.priceStore.info(for: FridgeFitPantryReading.id(for: milk))?.unitCost,
                       Money(Decimal(string: "4.5")!, .aud))
    }

    func test_expiryOnly_goesOnThePantryItem_noPriceSaved() async throws {
        let (pantryViewModel, environment) = setup()

        await pantryViewModel.addItem(name: "Bread", quantity: 1, unit: .pieces, category: .grain,
                                      expiryDate: TestDates.day(2))

        let bread = try XCTUnwrap(pantryViewModel.items.first)
        XCTAssertEqual(bread.expiryDate, TestDates.day(2))
        XCTAssertNil(environment.priceStore.info(for: FridgeFitPantryReading.id(for: bread)))
    }

    func test_noPriceNoExpiry_storesNothingExtra() async throws {
        let (pantryViewModel, environment) = setup()

        await pantryViewModel.addItem(name: "Rice", quantity: 1, unit: .kilograms, category: .grain)

        let rice = try XCTUnwrap(pantryViewModel.items.first)
        XCTAssertNil(environment.priceStore.info(for: FridgeFitPantryReading.id(for: rice)))
    }

    func test_duplicate_doesntOverwriteTheOldItemsPrice() async throws {
        let (pantryViewModel, environment) = setup()
        await pantryViewModel.addItem(name: "Eggs", quantity: 12, unit: .pieces, category: .dairy, pricePaid: 6)
        let eggs = try XCTUnwrap(pantryViewModel.items.first)

        // rejected as a duplicate, so the $100 shouldn't land anywhere
        await pantryViewModel.addItem(name: "eggs", quantity: 6, unit: .pieces, category: .dairy, pricePaid: 100)

        XCTAssertNotNil(pantryViewModel.duplicateItem)
        XCTAssertEqual(environment.priceStore.info(for: FridgeFitPantryReading.id(for: eggs))?.unitCost,
                       Money(Decimal(string: "0.5")!, .aud))
    }

    func test_withoutTheBudgetTab_addingStillWorks() async throws {
        let pantryViewModel = PantryViewModel(pantryRepository: InMemoryPantryRepository())

        await pantryViewModel.addItem(name: "Eggs", quantity: 12, unit: .pieces, category: .dairy, pricePaid: 6)

        XCTAssertEqual(pantryViewModel.items.map(\.name), ["Eggs"])
        XCTAssertNil(pantryViewModel.errorMessage)
    }
}
