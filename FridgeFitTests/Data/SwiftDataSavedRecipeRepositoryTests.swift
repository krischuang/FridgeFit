//
//  SwiftDataSavedRecipeRepositoryTests.swift
//  FridgeFitTests
//

import SwiftData
import XCTest
@testable import FridgeFit

/// Integration tests for recipes saved from Discover, against a real
/// in-memory `ModelContainer` (same approach as `SwiftDataPantryRepositoryTests`).
///
/// Every test is `async`: building a `ModelContainer` from a synchronous test
/// method aborts the test host - see `PersistenceConfigurationTests`.
@MainActor
final class SwiftDataSavedRecipeRepositoryTests: XCTestCase {
    private var container: PersistenceContainer!
    private var currentOwner: String? = "owner-a"
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var sut: SwiftDataSavedRecipeRepository!

    override func setUp() async throws {
        try await super.setUp()
        container = try PersistenceContainer(storage: .inMemory)
        sut = makeRepository(context: container.mainContext)
    }

    override func tearDown() async throws {
        sut = nil
        container = nil
        try await super.tearDown()
    }

    private func makeRepository(context: ModelContext) -> SwiftDataSavedRecipeRepository {
        SwiftDataSavedRecipeRepository(
            store: SwiftDataSavedRecipeStore(
                context: context,
                ownerIDProvider: { [unowned self] in self.currentOwner },
                now: { [unowned self] in self.clock }
            )
        )
    }

    private func recipe(
        spoonacularID: Int = 716429,
        title: String = "Garlic Pasta",
        ingredientNames: [String] = ["Pasta", "Garlic", "Parsley"]
    ) -> Recipe {
        Recipe(
            id: SaveOnlineRecipeUseCase.savedRecipeID(forOnlineRecipeID: spoonacularID),
            title: title,
            summary: "Quick weeknight pasta.",
            servings: 2,
            ingredients: ingredientNames.enumerated().map { index, name in
                RecipeIngredient(
                    ingredient: Ingredient(name: name, category: index == 0 ? .grain : .produce),
                    quantity: Double(100 * (index + 1)),
                    unit: index == 1 ? .pieces : .grams,
                    role: index == 2 ? .optional : .essential
                )
            },
            instructions: ["Boil the pasta.", "Fry the garlic.", "Toss together."],
            symbolName: "globe",
            cuisine: .italian,
            tastePreferences: [.savoury],
            dietaryLabels: [.vegetarian],
            totalCookingTimeInMinutes: 20,
            difficulty: .easy
        )
    }

    // MARK: - Round trip

    /// Every field - including ingredient order, roles, ids and all
    /// recommendation metadata - comes back exactly as saved.
    func test_save_thenFetchAll_roundTripsEveryField() async throws {
        let original = recipe()

        try await sut.save(original, sourceRecipeID: 716429)
        let loaded = try await sut.fetchAll()

        XCTAssertEqual(loaded, [original])
    }

    /// Reading back needs no provider at all - this is the whole point of
    /// saving. A brand-new repository over the same store sees the recipe.
    func test_savedRecipe_isReadableByAFreshRepository_withoutAnyProvider() async throws {
        try await sut.save(recipe(), sourceRecipeID: 716429)

        let reopened = makeRepository(context: container.mainContext)
        let loaded = try await reopened.fetchAll()

        XCTAssertEqual(loaded.map(\.title), ["Garlic Pasta"])
        XCTAssertEqual(loaded.first?.instructions.count, 3)
    }

    // MARK: - Identity

    func test_savingTwice_updatesOneRow_andReplacesIngredients() async throws {
        try await sut.save(recipe(), sourceRecipeID: 716429)
        clock = clock.addingTimeInterval(60)
        try await sut.save(recipe(title: "Garlic Pasta v2", ingredientNames: ["Pasta", "Garlic"]), sourceRecipeID: 716429)

        let loaded = try await sut.fetchAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.title, "Garlic Pasta v2")
        XCTAssertEqual(loaded.first?.ingredients.map(\.ingredient.name), ["Pasta", "Garlic"])

        let orphanLines = try container.mainContext.fetch(FetchDescriptor<SavedRecipeIngredientEntity>())
        XCTAssertEqual(orphanLines.count, 2, "Replaced lines must be deleted, not left orphaned")
    }

    func test_fetchAll_isNewestFirst() async throws {
        try await sut.save(recipe(spoonacularID: 1, title: "Older"), sourceRecipeID: 1)
        clock = clock.addingTimeInterval(60)
        try await sut.save(recipe(spoonacularID: 2, title: "Newer"), sourceRecipeID: 2)

        let titles = try await sut.fetchAll().map(\.title)
        XCTAssertEqual(titles, ["Newer", "Older"])
    }

    // MARK: - Ownership

    /// Two accounts on one device can save the same Spoonacular recipe and
    /// each keeps their own copy - which is why `recipeID` isn't `.unique`.
    func test_owners_areIsolated_evenForTheSameRecipe() async throws {
        try await sut.save(recipe(title: "A's copy"), sourceRecipeID: 716429)
        currentOwner = "owner-b"
        try await sut.save(recipe(title: "B's copy"), sourceRecipeID: 716429)

        let ownerBTitles = try await sut.fetchAll().map(\.title)
        XCTAssertEqual(ownerBTitles, ["B's copy"])
        currentOwner = "owner-a"
        let ownerATitles = try await sut.fetchAll().map(\.title)
        XCTAssertEqual(ownerATitles, ["A's copy"])
    }

    func test_noSignedInUser_isNotAuthenticated() async {
        currentOwner = nil
        do {
            try await sut.save(recipe(), sourceRecipeID: 1)
            XCTFail("Expected notAuthenticated")
        } catch {
            XCTAssertEqual(error as? SaveOnlineRecipeError, .notAuthenticated)
        }
    }

    // MARK: - Remove

    func test_remove_deletesRecipeAndItsLines() async throws {
        let saved = recipe()
        try await sut.save(saved, sourceRecipeID: 716429)

        try await sut.remove(id: saved.id)

        let remaining = try await sut.fetchAll()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<SavedRecipeIngredientEntity>()).isEmpty)
    }

    func test_remove_unknownRecipe_isNotAnError() async throws {
        try await sut.remove(id: UUID())
    }

    func test_remove_onlyAffectsTheCurrentOwner() async throws {
        let saved = recipe()
        try await sut.save(saved, sourceRecipeID: 716429)
        currentOwner = "owner-b"

        try await sut.remove(id: saved.id)

        currentOwner = "owner-a"
        let stillSaved = try await sut.fetchAll()
        XCTAssertEqual(stillSaved.count, 1)
    }

    // MARK: - Through the app's use case and graph

    func test_saveOnlineRecipeUseCase_writesToSwiftData() async throws {
        var online = OnlineRecipeFixtures.recipe(id: 42, title: "Online Bowl")
        online.steps = ["Cook rice.", "Top with egg."]

        let saved = try await SaveOnlineRecipeUseCase(repository: sut).execute(online)

        let loaded = try await sut.fetchAll()
        XCTAssertEqual(loaded.map(\.id), [saved.id])
        XCTAssertEqual(loaded.first?.instructions, ["Cook rice.", "Top with egg."])
    }

    func test_swiftDataGraph_providesSavedRecipeRepository_inTheSameStore() async throws {
        let dependencies = try AppDependencies(backend: .swiftData, storage: .inMemory, ownerIDProvider: { "graph-owner" })
        let repository = try XCTUnwrap(dependencies.savedRecipeRepository)

        try await repository.save(recipe(), sourceRecipeID: 716429)

        XCTAssertEqual(String(describing: type(of: repository)), "SwiftDataSavedRecipeRepository")
        let fromGraph = try await repository.fetchAll()
        XCTAssertEqual(fromGraph.count, 1)
    }

    func test_recipeViewModel_canSave_andShowsSavedRecipe() async throws {
        let viewModel = RecipeViewModel(
            recipeRepository: InMemoryRecipeRepository(recipes: []),
            pantryRepository: InMemoryPantryRepository(),
            savedRecipeRepository: sut
        )
        var online = OnlineRecipeFixtures.recipe(id: 7, title: "Saved Curry")
        online.steps = ["Simmer."]

        await viewModel.loadRecipes()
        await viewModel.saveOnlineRecipe(online)

        XCTAssertTrue(viewModel.canSaveRecipes)
        XCTAssertTrue(viewModel.isSaved(onlineRecipeID: 7))

        // A fresh view model over the same store - as after relaunch.
        let reloaded = RecipeViewModel(
            recipeRepository: InMemoryRecipeRepository(recipes: []),
            pantryRepository: InMemoryPantryRepository(),
            savedRecipeRepository: makeRepository(context: container.mainContext)
        )
        await reloaded.loadRecipes()
        XCTAssertEqual(reloaded.savedRecipes.map(\.title), ["Saved Curry"])
    }
}
