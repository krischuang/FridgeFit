//
//  SaveOnlineRecipeUseCaseTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class SaveOnlineRecipeUseCaseTests: XCTestCase {
    private func line(_ name: String, _ amount: Double, _ unit: MeasurementUnit?, raw: String, uncertain: Bool = false) -> OnlineRecipeIngredient {
        OnlineRecipeIngredient(providerID: nil, name: name, amount: amount, unit: unit, originalUnit: raw, quantityIsUncertain: uncertain)
    }

    private func onlineRecipe(id: Int = 716429, ingredients: [OnlineRecipeIngredient], steps: [String] = ["Cook it."]) -> OnlineRecipe {
        var recipe = OnlineRecipeFixtures.recipe(id: id, title: "Garlic Pasta")
        recipe.ingredients = ingredients
        recipe.steps = steps
        recipe.sourceName = "Example Kitchen"
        recipe.sourceURL = URL(string: "https://example.com/pasta")
        return recipe
    }

    // MARK: - Conversion

    func test_recipe_knownUnits_areEssential_andNamesCapitalized() throws {
        let recipe = try SaveOnlineRecipeUseCase.recipe(from: onlineRecipe(ingredients: [
            line("pasta", 250, .grams, raw: "g"),
            line("olive oil", 2, .tablespoons, raw: "tbsp"),
        ]))

        XCTAssertEqual(recipe.ingredients.map(\.ingredient.name), ["Pasta", "Olive Oil"])
        XCTAssertEqual(recipe.ingredients.map(\.unit), [.grams, .tablespoons])
        XCTAssertEqual(recipe.ingredients.map(\.role), [.essential, .essential])
        XCTAssertEqual(recipe.ingredients[0].quantity, 250)
    }

    func test_recipe_unknownUnit_becomesEssentialPieces() throws {
        let recipe = try SaveOnlineRecipeUseCase.recipe(from: onlineRecipe(ingredients: [line("garlic", 3, nil, raw: "cloves")]))

        XCTAssertEqual(recipe.ingredients.first?.unit, .pieces)
        XCTAssertEqual(recipe.ingredients.first?.quantity, 3)
        XCTAssertEqual(recipe.ingredients.first?.role, .essential)
    }

    func test_recipe_seasoningOrUncertainLines_becomeOptional() throws {
        let recipe = try SaveOnlineRecipeUseCase.recipe(from: onlineRecipe(ingredients: [
            line("salt", 1, nil, raw: "pinch"),
            line("pepper", 0, nil, raw: ""),
            line("green onion", 4, .pieces, raw: "servings", uncertain: true),
            line("chicken", 300, .grams, raw: "g"),
        ]))

        XCTAssertEqual(recipe.ingredients.map(\.role), [.optional, .optional, .optional, .essential])
        XCTAssertEqual(recipe.ingredients[1].quantity, 1, "A zero amount can't be a real requirement")
    }

    func test_recipe_duplicateNames_keepFirstLineOnly() throws {
        let recipe = try SaveOnlineRecipeUseCase.recipe(from: onlineRecipe(ingredients: [
            line("Butter", 1, .tablespoons, raw: "tbsp"),
            line("butter", 50, .grams, raw: "g"),
        ]))

        XCTAssertEqual(recipe.ingredients.count, 1)
        XCTAssertEqual(recipe.ingredients.first?.unit, .tablespoons)
    }

    func test_recipe_noUsableIngredients_throws() {
        XCTAssertThrowsError(try SaveOnlineRecipeUseCase.recipe(from: onlineRecipe(ingredients: [line("  ", 1, .grams, raw: "g")]))) { error in
            XCTAssertEqual(error as? SaveOnlineRecipeError, .noUsableIngredients)
        }
    }

    func test_recipe_missingSteps_pointToSource() throws {
        let recipe = try SaveOnlineRecipeUseCase.recipe(from: onlineRecipe(ingredients: [line("egg", 2, .pieces, raw: "")], steps: []))

        XCTAssertEqual(recipe.instructions.count, 1)
        XCTAssertTrue(recipe.instructions[0].contains("https://example.com/pasta"))
    }

    func test_recipe_summaryCreditsSource_andIconMarksItOnline() throws {
        let recipe = try SaveOnlineRecipeUseCase.recipe(from: onlineRecipe(ingredients: [line("egg", 2, .pieces, raw: "")]))

        XCTAssertTrue(recipe.summary.contains("Example Kitchen"))
        XCTAssertTrue(recipe.summary.contains("Spoonacular"))
        XCTAssertEqual(recipe.symbolName, "globe")
    }

    func test_savedRecipeID_isStable_andDistinctPerRecipe() {
        XCTAssertEqual(SaveOnlineRecipeUseCase.savedRecipeID(forOnlineRecipeID: 42), SaveOnlineRecipeUseCase.savedRecipeID(forOnlineRecipeID: 42))
        XCTAssertNotEqual(SaveOnlineRecipeUseCase.savedRecipeID(forOnlineRecipeID: 42), SaveOnlineRecipeUseCase.savedRecipeID(forOnlineRecipeID: 43))
    }

    // MARK: - Execute

    func test_execute_savesConvertedRecipe_withSourceID() async throws {
        let repository = InMemorySavedRecipeRepository()
        let useCase = SaveOnlineRecipeUseCase(repository: repository)

        let recipe = try await useCase.execute(onlineRecipe(id: 7, ingredients: [line("egg", 2, .pieces, raw: "")]))

        XCTAssertEqual(repository.recipes.map(\.id), [recipe.id])
        XCTAssertEqual(repository.sourceIDs[recipe.id], 7)
    }

    func test_execute_savingTwice_doesNotDuplicate() async throws {
        let repository = InMemorySavedRecipeRepository()
        let useCase = SaveOnlineRecipeUseCase(repository: repository)
        let online = onlineRecipe(ingredients: [line("egg", 2, .pieces, raw: "")])

        try await useCase.execute(online)
        try await useCase.execute(online)

        XCTAssertEqual(repository.recipes.count, 1)
    }

    func test_execute_storageFailure_mapsToSaveFailed() async {
        let repository = InMemorySavedRecipeRepository()
        repository.failure = URLError(.notConnectedToInternet)

        do {
            try await SaveOnlineRecipeUseCase(repository: repository).execute(onlineRecipe(ingredients: [line("egg", 2, .pieces, raw: "")]))
            XCTFail("Expected saveFailed")
        } catch {
            XCTAssertEqual(error as? SaveOnlineRecipeError, .saveFailed)
        }
    }

    func test_execute_notAuthenticated_isPreserved() async {
        let repository = InMemorySavedRecipeRepository()
        repository.failure = SaveOnlineRecipeError.notAuthenticated

        do {
            try await SaveOnlineRecipeUseCase(repository: repository).execute(onlineRecipe(ingredients: [line("egg", 2, .pieces, raw: "")]))
            XCTFail("Expected notAuthenticated")
        } catch {
            XCTAssertEqual(error as? SaveOnlineRecipeError, .notAuthenticated)
        }
    }

    func test_removeUseCase_storageFailure_mapsToRemoveFailed() async {
        let repository = InMemorySavedRecipeRepository()
        repository.failure = URLError(.timedOut)

        do {
            try await RemoveSavedRecipeUseCase(repository: repository).execute(id: UUID())
            XCTFail("Expected removeFailed")
        } catch {
            XCTAssertEqual(error as? SaveOnlineRecipeError, .removeFailed)
        }
    }

    func test_errorMessages_areHumanReadable() {
        let all: [SaveOnlineRecipeError] = [.noUsableIngredients, .notAuthenticated, .saveFailed, .removeFailed, .loadFailed]
        for error in all {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error) needs a message")
        }
    }
}
