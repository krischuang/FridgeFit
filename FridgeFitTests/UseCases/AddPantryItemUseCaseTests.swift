//
//  AddPantryItemUseCaseTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class AddPantryItemUseCaseTests: XCTestCase {
    private func makeUseCase(seedItems: [PantryItem] = []) -> (AddPantryItemUseCase, InMemoryPantryRepository) {
        let repository = InMemoryPantryRepository(seedItems: seedItems)
        return (AddPantryItemUseCase(pantryRepository: repository), repository)
    }

    func test_addPantryItem_succeeds_withValidNameAndQuantity() async throws {
        let (useCase, repository) = makeUseCase()

        let item = try await useCase.execute(name: "Chicken", quantity: 400, unit: .grams, category: .meat)

        XCTAssertEqual(item.name, "Chicken")
        let all = try await repository.fetchAll()
        XCTAssertEqual(all.count, 1)
    }

    func test_addPantryItem_succeeds_withZeroQuantity() async throws {
        let (useCase, _) = makeUseCase()

        _ = try await useCase.execute(name: "Salt", quantity: 0, unit: .grams, category: .spice)
    }

    func test_addPantryItem_fails_whenIngredientNameIsEmpty() async {
        let (useCase, _) = makeUseCase()

        do {
            _ = try await useCase.execute(name: "   ", quantity: 1, unit: .pieces, category: .other)
            XCTFail("Expected emptyIngredientName error")
        } catch {
            XCTAssertEqual(error as? AddPantryItemError, .emptyIngredientName)
        }
    }

    func test_addPantryItem_fails_whenQuantityIsNegative() async {
        let (useCase, _) = makeUseCase()

        do {
            _ = try await useCase.execute(name: "Flour", quantity: -1, unit: .grams, category: .grain)
            XCTFail("Expected invalidQuantity error")
        } catch {
            XCTAssertEqual(error as? AddPantryItemError, .invalidQuantity)
        }
    }

    func test_addPantryItem_fails_whenIngredientAlreadyExists() async throws {
        let existing = PantryItem(ingredient: Ingredient(name: "Chicken", category: .meat), quantity: 200, unit: .grams)
        let (useCase, repository) = makeUseCase(seedItems: [existing])

        do {
            _ = try await useCase.execute(name: "Chicken", quantity: 300, unit: .grams, category: .meat)
            XCTFail("Expected duplicateIngredient error")
        } catch {
            XCTAssertEqual(error as? AddPantryItemError, .duplicateIngredient(name: "Chicken"))
        }
        // Original entry should be untouched, not merged or duplicated.
        let all = try await repository.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.quantity, 200)
    }

    func test_addPantryItem_treatsNamesCaseInsensitively_asDuplicates() async {
        let existing = PantryItem(ingredient: Ingredient(name: "Chicken", category: .meat), quantity: 200, unit: .grams)
        let (useCase, _) = makeUseCase(seedItems: [existing])

        do {
            _ = try await useCase.execute(name: "  chicken  ", quantity: 100, unit: .grams, category: .meat)
            XCTFail("Expected duplicateIngredient error")
        } catch {
            XCTAssertEqual(error as? AddPantryItemError, .duplicateIngredient(name: "Chicken"))
        }
    }
}
