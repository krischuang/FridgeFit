//
//  AddDetectedIngredientsUseCaseTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class AddDetectedIngredientsUseCaseTests: XCTestCase {
    private func draft(
        name: String,
        category: IngredientCategory = .other,
        quantityText: String = "2",
        unit: MeasurementUnit = .pieces,
        isSelected: Bool = true,
        isAlreadyInPantry: Bool = false
    ) -> DetectedIngredientDraft {
        var draft = DetectedIngredientDraft(
            detection: DetectedIngredient(
                name: name,
                category: category,
                visibleCount: 2,
                confidence: .high,
                isAlreadyInPantry: isAlreadyInPantry
            )
        )
        draft.isSelected = isSelected
        draft.quantityText = quantityText
        draft.unit = unit
        return draft
    }

    /// Detections must reach storage through the existing pantry use case,
    /// which is what actually writes to the repository.
    func test_addDetectedIngredients_storesItemsThroughPantryRepository() async throws {
        let repository = InMemoryPantryRepository()
        let useCase = AddDetectedIngredientsUseCase(pantryRepository: repository)

        let summary = await useCase.execute(drafts: [
            draft(name: "Milk", category: .dairy, quantityText: "1", unit: .liters),
            draft(name: "Tomato", category: .produce, quantityText: "3")
        ])

        XCTAssertEqual(summary.addedNames, ["Milk", "Tomato"])
        XCTAssertTrue(summary.isCompleteSuccess)

        let stored = try await repository.fetchAll()
        XCTAssertEqual(stored.map(\.name), ["Milk", "Tomato"])
        XCTAssertEqual(stored.first?.ingredient.category, .dairy)
        XCTAssertEqual(stored.first?.quantity, 1)
        XCTAssertEqual(stored.first?.unit, .liters)
    }

    /// The scanner must respect `AddPantryItemUseCase`'s existing duplicate
    /// rule rather than merging or double-adding.
    func test_addDetectedIngredients_respectsExistingDuplicateRule() async throws {
        let repository = InMemoryPantryRepository(seedItems: [
            PantryItem(ingredient: Ingredient(name: "Milk", category: .dairy), quantity: 500, unit: .milliliters)
        ])
        let useCase = AddDetectedIngredientsUseCase(pantryRepository: repository)

        let summary = await useCase.execute(drafts: [draft(name: "milk", category: .dairy)])

        XCTAssertTrue(summary.addedNames.isEmpty)
        XCTAssertEqual(summary.duplicateNames, ["Milk"])
        XCTAssertFalse(summary.isCompleteSuccess)

        let stored = try await repository.fetchAll()
        XCTAssertEqual(stored.count, 1, "Duplicate must not create a second row")
        XCTAssertEqual(stored.first?.quantity, 500, "Existing quantity must be left alone")
    }

    /// One duplicate must not stop the rest of a scan going in.
    func test_addDetectedIngredients_addsOthers_whenOneIsDuplicate() async throws {
        let repository = InMemoryPantryRepository(seedItems: [
            PantryItem(ingredient: Ingredient(name: "Eggs", category: .other), quantity: 6, unit: .pieces)
        ])
        let useCase = AddDetectedIngredientsUseCase(pantryRepository: repository)

        let summary = await useCase.execute(drafts: [
            draft(name: "Eggs"),
            draft(name: "Tomato", category: .produce),
            draft(name: "Chicken", category: .meat)
        ])

        XCTAssertEqual(summary.addedNames, ["Tomato", "Chicken"])
        XCTAssertEqual(summary.duplicateNames, ["Eggs"])
        let stored = try await repository.fetchAll()
        XCTAssertEqual(stored.count, 3)
    }

    func test_addDetectedIngredients_reportsFailure_forUnusableQuantity() async throws {
        let repository = InMemoryPantryRepository()
        let useCase = AddDetectedIngredientsUseCase(pantryRepository: repository)

        let summary = await useCase.execute(drafts: [draft(name: "Rice", quantityText: "not a number")])

        XCTAssertTrue(summary.addedNames.isEmpty)
        XCTAssertEqual(summary.failures.map(\.name), ["Rice"])
        let stored = try await repository.fetchAll()
        XCTAssertTrue(stored.isEmpty)
    }

    /// `AddPantryItemUseCase` owns name validation - the scanner must not
    /// work around it.
    func test_addDetectedIngredients_reportsFailure_forBlankName() async throws {
        let repository = InMemoryPantryRepository()
        let useCase = AddDetectedIngredientsUseCase(pantryRepository: repository)

        var blank = draft(name: "Mystery Item")
        blank.name = "   "

        let summary = await useCase.execute(drafts: [blank])

        XCTAssertTrue(summary.addedNames.isEmpty)
        XCTAssertEqual(summary.failures.count, 1)
        let stored = try await repository.fetchAll()
        XCTAssertTrue(stored.isEmpty)
    }

    func test_summary_userMessage_describesMixedOutcome() {
        let summary = AddDetectedIngredientsSummary(
            addedNames: ["Tomato", "Chicken"],
            duplicateNames: ["Milk"],
            failures: []
        )

        XCTAssertTrue(summary.userMessage.contains("Added 2 ingredients"))
        XCTAssertTrue(summary.userMessage.contains("Milk"))
    }

    func test_summary_userMessage_whenNothingAdded() {
        let summary = AddDetectedIngredientsSummary(addedNames: [], duplicateNames: [], failures: [])

        XCTAssertEqual(summary.userMessage, "Nothing was added to your pantry.")
        XCTAssertEqual(summary.addedCount, 0)
    }
}
