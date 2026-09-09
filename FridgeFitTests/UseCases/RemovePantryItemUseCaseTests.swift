//
//  RemovePantryItemUseCaseTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class RemovePantryItemUseCaseTests: XCTestCase {
    func test_removePantryItem_succeeds_whenItemExists() async throws {
        let item = PantryItem(ingredient: Ingredient(name: "Onion", category: .produce), quantity: 3, unit: .pieces)
        let repository = InMemoryPantryRepository(seedItems: [item])
        let useCase = RemovePantryItemUseCase(pantryRepository: repository)

        let removed = try await useCase.execute(id: item.id)

        XCTAssertEqual(removed.id, item.id)
        let all = try await repository.fetchAll()
        XCTAssertTrue(all.isEmpty)
    }

    func test_removePantryItem_fails_whenItemNoLongerExists() async {
        let repository = InMemoryPantryRepository(seedItems: [])
        let useCase = RemovePantryItemUseCase(pantryRepository: repository)

        do {
            _ = try await useCase.execute(id: UUID())
            XCTFail("Expected pantryItemNotFound error")
        } catch {
            XCTAssertEqual(error as? RemovePantryItemError, .pantryItemNotFound)
        }
    }
}
