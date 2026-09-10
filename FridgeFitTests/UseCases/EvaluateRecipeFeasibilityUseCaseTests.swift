//
//  EvaluateRecipeFeasibilityUseCaseTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class EvaluateRecipeFeasibilityUseCaseTests: XCTestCase {
    // Mirrors the spec's worked example: 4 essential ingredients + 1
    // optional (Parsley).
    private func referenceRecipe() -> Recipe {
        Recipe(
            title: "Chicken Pasta",
            summary: "Test fixture recipe.",
            ingredients: [
                RecipeIngredient(ingredient: Ingredient(name: "Chicken Breast", category: .meat), quantity: 400, unit: .grams, role: .essential),
                RecipeIngredient(ingredient: Ingredient(name: "Pasta", category: .grain), quantity: 250, unit: .grams, role: .essential),
                RecipeIngredient(ingredient: Ingredient(name: "Garlic", category: .produce), quantity: 2, unit: .pieces, role: .essential),
                RecipeIngredient(ingredient: Ingredient(name: "Cream", category: .dairy), quantity: 200, unit: .milliliters, role: .essential),
                RecipeIngredient(ingredient: Ingredient(name: "Parsley", category: .produce), quantity: 1, unit: .tablespoons, role: .optional),
            ],
            instructions: ["Cook it."]
        )
    }

    private func fullPantry() -> [PantryItem] {
        [
            PantryItem(ingredient: Ingredient(name: "Chicken Breast", category: .meat), quantity: 500, unit: .grams),
            PantryItem(ingredient: Ingredient(name: "Pasta", category: .grain), quantity: 500, unit: .grams),
            PantryItem(ingredient: Ingredient(name: "Garlic", category: .produce), quantity: 3, unit: .pieces),
            PantryItem(ingredient: Ingredient(name: "Cream", category: .dairy), quantity: 300, unit: .milliliters),
        ]
    }

    private func makeUseCase(pantryItems: [PantryItem]) -> EvaluateRecipeFeasibilityUseCase {
        EvaluateRecipeFeasibilityUseCase(pantryRepository: InMemoryPantryRepository(seedItems: pantryItems))
    }

    // MARK: - Scenario 1: fully stocked pantry

    func test_scenario1_fullPantry_isMakeable_with100PercentCoverage() async throws {
        let useCase = makeUseCase(pantryItems: fullPantry())

        let result = try await useCase.execute(recipe: referenceRecipe())

        XCTAssertEqual(result.status, .makeable)
        XCTAssertTrue(result.canMakeRecipe)
        XCTAssertEqual(result.coveragePercentage, 100)
        XCTAssertEqual(result.matchedCount, 4)
        XCTAssertEqual(result.totalRequiredCount, 4)
        XCTAssertTrue(result.missingIngredients.isEmpty)
        XCTAssertTrue(result.insufficientIngredients.isEmpty)
    }

    // MARK: - Scenario 2: essential ingredient entirely absent

    func test_scenario2_missingEssentialIngredient_isReportedAndLowersCoverage() async throws {
        let pantryWithoutCream = fullPantry().filter { $0.name != "Cream" }
        let useCase = makeUseCase(pantryItems: pantryWithoutCream)

        let result = try await useCase.execute(recipe: referenceRecipe())

        XCTAssertNotEqual(result.status, .makeable)
        XCTAssertFalse(result.canMakeRecipe)
        XCTAssertEqual(result.missingIngredients.map(\.ingredient.name), ["Cream"])
        XCTAssertEqual(result.coveragePercentage, 75)
    }

    // MARK: - Scenario 3: safe unit conversion

    func test_scenario3_kilogramsInPantry_satisfiesGramsRequirement() async throws {
        let pantry = [PantryItem(ingredient: Ingredient(name: "Chicken Breast", category: .meat), quantity: 0.5, unit: .kilograms)]
        let recipe = Recipe(
            title: "Just Chicken",
            summary: "Test fixture.",
            ingredients: [RecipeIngredient(ingredient: Ingredient(name: "Chicken Breast", category: .meat), quantity: 400, unit: .grams, role: .essential)],
            instructions: ["Cook it."]
        )
        let useCase = makeUseCase(pantryItems: pantry)

        let result = try await useCase.execute(recipe: recipe)

        XCTAssertEqual(result.status, .makeable)
        XCTAssertEqual(result.evaluatedIngredients.first?.availability, .available)
    }

    func test_millilitersToLitersConversion_satisfiesRequirement() async throws {
        let pantry = [PantryItem(ingredient: Ingredient(name: "Cream", category: .dairy), quantity: 1, unit: .liters)]
        let recipe = Recipe(
            title: "Just Cream",
            summary: "Test fixture.",
            ingredients: [RecipeIngredient(ingredient: Ingredient(name: "Cream", category: .dairy), quantity: 750, unit: .milliliters, role: .essential)],
            instructions: ["Pour it."]
        )
        let useCase = makeUseCase(pantryItems: pantry)

        let result = try await useCase.execute(recipe: recipe)

        XCTAssertEqual(result.evaluatedIngredients.first?.availability, .available)
    }

    // MARK: - Scenario 4: numerically-equal quantities in incompatible/unrelated ingredients must not match

    func test_scenario4_unrelatedIngredientWithEqualQuantity_doesNotSatisfyRequirement() async throws {
        let pantry = [PantryItem(ingredient: Ingredient(name: "Milk", category: .dairy), quantity: 500, unit: .milliliters)]
        let recipe = Recipe(
            title: "Just Flour",
            summary: "Test fixture.",
            ingredients: [RecipeIngredient(ingredient: Ingredient(name: "Flour", category: .grain), quantity: 500, unit: .grams, role: .essential)],
            instructions: ["Bake it."]
        )
        let useCase = makeUseCase(pantryItems: pantry)

        let result = try await useCase.execute(recipe: recipe)

        XCTAssertEqual(result.evaluatedIngredients.first?.availability, .missing)
    }

    func test_incompatibleUnitDimensions_sameIngredientName_failsClosedAsUnverified() async throws {
        // Same ingredient, but stored in the pantry using a unit from a
        // different dimension than the recipe needs - must not guess.
        let pantry = [PantryItem(ingredient: Ingredient(name: "Cream", category: .dairy), quantity: 300, unit: .grams)]
        let recipe = Recipe(
            title: "Just Cream",
            summary: "Test fixture.",
            ingredients: [RecipeIngredient(ingredient: Ingredient(name: "Cream", category: .dairy), quantity: 200, unit: .milliliters, role: .essential)],
            instructions: ["Pour it."]
        )
        let useCase = makeUseCase(pantryItems: pantry)

        let result = try await useCase.execute(recipe: recipe)

        XCTAssertEqual(result.evaluatedIngredients.first?.availability, .quantityUnverified)
    }

    // MARK: - Scenario 5: optional ingredient missing doesn't block makeability

    func test_scenario5_missingOptionalIngredient_doesNotBlockMakeability() async throws {
        let useCase = makeUseCase(pantryItems: fullPantry()) // no Parsley seeded

        let result = try await useCase.execute(recipe: referenceRecipe())

        XCTAssertEqual(result.status, .makeable)
        XCTAssertTrue(result.canMakeRecipe)
        XCTAssertEqual(result.optionalMissingIngredients.map(\.ingredient.name), ["Parsley"])
    }

    // MARK: - Name matching

    func test_exactIngredientMatch_isAvailable() async throws {
        let pantry = [PantryItem(ingredient: Ingredient(name: "Garlic", category: .produce), quantity: 5, unit: .pieces)]
        let recipe = singleIngredientRecipe(name: "Garlic", quantity: 2, unit: .pieces)

        let result = try await makeUseCase(pantryItems: pantry).execute(recipe: recipe)

        XCTAssertEqual(result.evaluatedIngredients.first?.availability, .available)
    }

    func test_caseInsensitiveMatching() async throws {
        let pantry = [PantryItem(ingredient: Ingredient(name: "garlic", category: .produce), quantity: 5, unit: .pieces)]
        let recipe = singleIngredientRecipe(name: "GARLIC", quantity: 2, unit: .pieces)

        let result = try await makeUseCase(pantryItems: pantry).execute(recipe: recipe)

        XCTAssertEqual(result.evaluatedIngredients.first?.availability, .available)
    }

    func test_trimmedNameMatching() async throws {
        let pantry = [PantryItem(ingredient: Ingredient(name: "  Garlic  ", category: .produce), quantity: 5, unit: .pieces)]
        let recipe = singleIngredientRecipe(name: "Garlic", quantity: 2, unit: .pieces)

        let result = try await makeUseCase(pantryItems: pantry).execute(recipe: recipe)

        XCTAssertEqual(result.evaluatedIngredients.first?.availability, .available)
    }

    // MARK: - Quantity sufficiency

    func test_sufficientQuantity_isAvailable() async throws {
        let pantry = [PantryItem(ingredient: Ingredient(name: "Rice", category: .grain), quantity: 500, unit: .grams)]
        let recipe = singleIngredientRecipe(name: "Rice", quantity: 300, unit: .grams)

        let result = try await makeUseCase(pantryItems: pantry).execute(recipe: recipe)

        XCTAssertEqual(result.evaluatedIngredients.first?.availability, .available)
    }

    func test_insufficientQuantity_reportsShortfall() async throws {
        let pantry = [PantryItem(ingredient: Ingredient(name: "Rice", category: .grain), quantity: 100, unit: .grams)]
        let recipe = singleIngredientRecipe(name: "Rice", quantity: 300, unit: .grams)

        let result = try await makeUseCase(pantryItems: pantry).execute(recipe: recipe)

        let evaluation = try XCTUnwrap(result.evaluatedIngredients.first)
        XCTAssertEqual(evaluation.availability, .insufficient)
        XCTAssertEqual(evaluation.missingQuantity, 200)
    }

    // MARK: - Empty / multiple missing

    func test_emptyPantry_allEssentialIngredientsMissing_isNotMakeable() async throws {
        let result = try await makeUseCase(pantryItems: []).execute(recipe: referenceRecipe())

        XCTAssertEqual(result.status, .notMakeable)
        XCTAssertEqual(result.coveragePercentage, 0)
        XCTAssertEqual(result.matchedCount, 0)
        XCTAssertEqual(result.missingIngredients.count, 4)
    }

    func test_multipleMissingIngredients_belowHalfCoverage_isNotMakeable() async throws {
        // Only Chicken Breast present out of 4 essential -> 25% coverage.
        let pantry = [PantryItem(ingredient: Ingredient(name: "Chicken Breast", category: .meat), quantity: 500, unit: .grams)]

        let result = try await makeUseCase(pantryItems: pantry).execute(recipe: referenceRecipe())

        XCTAssertEqual(result.status, .notMakeable)
        XCTAssertEqual(result.coveragePercentage, 25)
    }

    func test_multipleMissingIngredients_atHalfCoverage_isAlmostMakeable() async throws {
        // Chicken Breast and Pasta present out of 4 essential -> 50% coverage.
        let pantry = [
            PantryItem(ingredient: Ingredient(name: "Chicken Breast", category: .meat), quantity: 500, unit: .grams),
            PantryItem(ingredient: Ingredient(name: "Pasta", category: .grain), quantity: 500, unit: .grams),
        ]

        let result = try await makeUseCase(pantryItems: pantry).execute(recipe: referenceRecipe())

        XCTAssertEqual(result.status, .almostMakeable)
        XCTAssertEqual(result.coveragePercentage, 50)
    }

    // MARK: - Recipe with no essential ingredients

    func test_recipeWithOnlyOptionalIngredients_isTriviallyMakeable() async throws {
        let recipe = Recipe(
            title: "Garnish Only",
            summary: "Test fixture.",
            ingredients: [RecipeIngredient(ingredient: Ingredient(name: "Parsley", category: .produce), quantity: 1, unit: .tablespoons, role: .optional)],
            instructions: ["Sprinkle it on."]
        )

        let result = try await makeUseCase(pantryItems: []).execute(recipe: recipe)

        XCTAssertEqual(result.status, .makeable)
        XCTAssertEqual(result.coveragePercentage, 100)
    }

    private func singleIngredientRecipe(name: String, quantity: Double, unit: MeasurementUnit) -> Recipe {
        Recipe(
            title: "Single Ingredient Test",
            summary: "Test fixture.",
            ingredients: [RecipeIngredient(ingredient: Ingredient(name: name, category: .other), quantity: quantity, unit: unit, role: .essential)],
            instructions: ["Use it."]
        )
    }
}
