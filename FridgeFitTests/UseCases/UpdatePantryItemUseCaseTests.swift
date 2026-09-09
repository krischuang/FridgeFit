//
//  UpdatePantryItemUseCaseTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class UpdatePantryItemUseCaseTests: XCTestCase {
    func test_updatePantryItem_succeeds_withValidQuantity() async throws {
        let item = PantryItem(ingredient: Ingredient(name: "Chicken", category: .meat), quantity: 200, unit: .grams)
        let repository = InMemoryPantryRepository(seedItems: [item])
        let useCase = UpdatePantryItemUseCase(pantryRepository: repository)

        let updated = try await useCase.execute(id: item.id, quantity: 500, unit: .grams)

        XCTAssertEqual(updated.quantity, 500)
        let all = try await repository.fetchAll()
        XCTAssertEqual(all.first?.quantity, 500)
    }

    func test_updatePantryItem_fails_whenQuantityIsNegative() async {
        let item = PantryItem(ingredient: Ingredient(name: "Chicken", category: .meat), quantity: 200, unit: .grams)
        let repository = InMemoryPantryRepository(seedItems: [item])
        let useCase = UpdatePantryItemUseCase(pantryRepository: repository)

        do {
            _ = try await useCase.execute(id: item.id, quantity: -1, unit: .grams)
            XCTFail("Expected invalidQuantity error")
        } catch {
            XCTAssertEqual(error as? AddPantryItemError, .invalidQuantity)
        }
    }

    func test_updatePantryItem_fails_whenItemNoLongerExists() async {
        let repository = InMemoryPantryRepository(seedItems: [])
        let useCase = UpdatePantryItemUseCase(pantryRepository: repository)

        do {
            _ = try await useCase.execute(id: UUID(), quantity: 100, unit: .grams)
            XCTFail("Expected itemNotFound error")
        } catch {
            XCTAssertEqual(error as? UpdatePantryItemError, .itemNotFound)
        }
    }
}
