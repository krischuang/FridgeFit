//
//  PantryViewModelTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class PantryViewModelTests: XCTestCase {
    private func makeViewModel(seedItems: [PantryItem] = []) -> PantryViewModel {
        PantryViewModel(pantryRepository: InMemoryPantryRepository(seedItems: seedItems))
    }

    func test_pantryViewModel_loadItems_loadsSeededItems() async {
        let seedItems = [PantryItem(ingredient: Ingredient(name: "Rice", category: .grain), quantity: 500, unit: .grams)]
        let viewModel = makeViewModel(seedItems: seedItems)

        await viewModel.loadItems()

        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.items.first?.name, "Rice")
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_pantryViewModel_addItem_appendsNewItem_andClearsErrorMessage() async {
        let viewModel = makeViewModel()

        await viewModel.addItem(name: "Eggs", quantity: 6, unit: .pieces, category: .other)

        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertNil(viewModel.errorMessage)
    }

    func test_pantryViewModel_addItem_setsHumanReadableErrorMessage_whenDuplicate() async {
        let seedItems = [PantryItem(ingredient: Ingredient(name: "Chicken", category: .meat), quantity: 200, unit: .grams)]
        let viewModel = makeViewModel(seedItems: seedItems)
        await viewModel.loadItems()

        await viewModel.addItem(name: "Chicken", quantity: 100, unit: .grams, category: .meat)

        XCTAssertEqual(viewModel.items.count, 1)
        let message = try? XCTUnwrap(viewModel.errorMessage)
        XCTAssertEqual(message, AddPantryItemError.duplicateIngredient(name: "Chicken").errorDescription)
    }

    func test_pantryViewModel_addItem_exposesDuplicateItem_forGuidedRecovery() async {
        let existing = PantryItem(ingredient: Ingredient(name: "Chicken", category: .meat), quantity: 200, unit: .grams)
        let viewModel = makeViewModel(seedItems: [existing])
        await viewModel.loadItems()

        await viewModel.addItem(name: "Chicken", quantity: 100, unit: .grams, category: .meat)

        XCTAssertEqual(viewModel.duplicateItem?.id, existing.id)
    }

    func test_pantryViewModel_updateQuantity_changesExistingItem_andClearsErrorMessage() async {
        let existing = PantryItem(ingredient: Ingredient(name: "Chicken", category: .meat), quantity: 200, unit: .grams)
        let viewModel = makeViewModel(seedItems: [existing])
        await viewModel.loadItems()

        await viewModel.updateQuantity(for: existing, quantity: 600, unit: .grams)

        XCTAssertEqual(viewModel.items.first?.quantity, 600)
        XCTAssertNil(viewModel.errorMessage)
    }

    func test_pantryViewModel_updateQuantity_setsErrorMessage_whenQuantityIsInvalid() async {
        let existing = PantryItem(ingredient: Ingredient(name: "Chicken", category: .meat), quantity: 200, unit: .grams)
        let viewModel = makeViewModel(seedItems: [existing])
        await viewModel.loadItems()

        await viewModel.updateQuantity(for: existing, quantity: -1, unit: .grams)

        XCTAssertEqual(viewModel.errorMessage, AddPantryItemError.invalidQuantity.errorDescription)
        XCTAssertEqual(viewModel.items.first?.quantity, 200)
    }

    func test_pantryViewModel_removeItem_removesFromItems() async {
        let target = PantryItem(ingredient: Ingredient(name: "Onion", category: .produce), quantity: 3, unit: .pieces)
        let viewModel = makeViewModel(seedItems: [target])
        await viewModel.loadItems()

        await viewModel.removeItem(target)

        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertNil(viewModel.removalErrorMessage)
    }

    func test_pantryViewModel_removeItem_setsHumanReadableErrorMessage_whenItemNoLongerExists() async throws {
        let target = PantryItem(ingredient: Ingredient(name: "Onion", category: .produce), quantity: 3, unit: .pieces)
        let repository = InMemoryPantryRepository(seedItems: [target])
        let viewModel = PantryViewModel(pantryRepository: repository)
        await viewModel.loadItems()
        // Item got removed elsewhere before the swipe was handled.
        try await repository.remove(id: target.id)

        await viewModel.removeItem(target)

        XCTAssertEqual(viewModel.removalErrorMessage, RemovePantryItemError.pantryItemNotFound.errorDescription)
    }
}
