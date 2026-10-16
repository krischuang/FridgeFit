//
//  OnlineRecipeContextAwareIntegrationTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// Proves the integration's central claim: a recipe saved from Discover goes
/// through **main's existing** feasibility, suitability and ranking - not a
/// parallel engine - and does so without weakening any of their guarantees.
///
/// Everything here runs on `MockOnlineRecipeService` and in-memory
/// repositories. No provider access and no Firestore access.
@MainActor
final class OnlineRecipeContextAwareIntegrationTests: XCTestCase {

    private typealias Fixture = RecommendationFixture

    /// An online recipe whose ingredients are expressed in units
    /// `MeasurementUnit` understands, so the quantity path is exercised.
    private func onlineRecipe(
        id: Int = 4242,
        title: String = "Online Tomato Pasta",
        readyInMinutes: Int? = 20,
        ingredients: [OnlineRecipeIngredient]? = nil
    ) -> OnlineRecipe {
        OnlineRecipe(
            id: id,
            title: title,
            imageURL: nil,
            readyInMinutes: readyInMinutes,
            servings: 2,
            summary: "From the provider.",
            sourceName: "Example Kitchen",
            sourceURL: nil,
            healthScore: nil,
            diets: ["gluten free", "vegan"],
            ingredients: ingredients ?? [
                OnlineRecipeIngredient(providerID: 1, name: "Pasta", amount: 200, unit: .grams, originalUnit: "g"),
                OnlineRecipeIngredient(providerID: 2, name: "Tomato", amount: 300, unit: .grams, originalUnit: "g"),
            ],
            steps: ["Boil the pasta.", "Add the tomato."],
            containsIntolerances: []
        )
    }

    // MARK: - Participation in context-aware ranking

    func test_savedOnlineRecipe_isRankedByTheExistingEngine() async throws {
        let saved = InMemorySavedRecipeRepository()
        try await SaveOnlineRecipeUseCase(repository: saved).execute(onlineRecipe())

        let catalogue = CompositeRecipeRepository(
            bundled: InMemoryRecipeRepository(recipes: [Fixture.recipe(title: "Bundled Pasta")]),
            savedRecipes: saved
        )
        let useCase = GenerateContextAwareRecommendationsUseCase(
            recipeRepository: catalogue,
            pantryRepository: InMemoryPantryRepository(seedItems: Fixture.stockedPantry)
        )

        let recommendations = try await useCase.execute(context: .unrestricted, now: Fixture.now)

        let titles = recommendations.map(\.suitability.recipe.title)
        XCTAssertTrue(
            titles.contains("Online Tomato Pasta"),
            "A saved online recipe must reach the recommendation list through the shared repository"
        )
        XCTAssertTrue(titles.contains("Bundled Pasta"), "Bundled recipes must keep working alongside it")
    }

    func test_savedOnlineRecipe_earnsReadyToCookFromRealQuantities() async throws {
        // The pantry genuinely holds enough of both, in convertible units.
        let saved = InMemorySavedRecipeRepository()
        try await SaveOnlineRecipeUseCase(repository: saved).execute(onlineRecipe())

        let catalogue = CompositeRecipeRepository(
            bundled: InMemoryRecipeRepository(recipes: []),
            savedRecipes: saved
        )
        let useCase = GenerateContextAwareRecommendationsUseCase(
            recipeRepository: catalogue,
            pantryRepository: InMemoryPantryRepository(seedItems: Fixture.stockedPantry)
        )

        let recommendations = try await useCase.execute(context: .unrestricted, now: Fixture.now)
        let online = try XCTUnwrap(recommendations.first { $0.suitability.recipe.title == "Online Tomato Pasta" })

        XCTAssertEqual(online.suitability.readiness, .readyToCook)
        XCTAssertTrue(online.rankingReasons.contains(.readyToCook))
    }

    func test_providerCookingTimeIsCarriedIntoRanking() async throws {
        let saved = InMemorySavedRecipeRepository()
        try await SaveOnlineRecipeUseCase(repository: saved).execute(onlineRecipe(readyInMinutes: 20))

        let catalogue = CompositeRecipeRepository(
            bundled: InMemoryRecipeRepository(recipes: []),
            savedRecipes: saved
        )
        let useCase = GenerateContextAwareRecommendationsUseCase(
            recipeRepository: catalogue,
            pantryRepository: InMemoryPantryRepository(seedItems: Fixture.stockedPantry)
        )

        let context = CookingContext(maximumCookingTime: .thirtyMinutes)
        let recommendations = try await useCase.execute(context: context, now: Fixture.now)
        let online = try XCTUnwrap(recommendations.first { $0.suitability.recipe.title == "Online Tomato Pasta" })

        XCTAssertEqual(online.suitability.recipe.totalCookingTimeInMinutes, 20)
        XCTAssertTrue(
            online.rankingReasons.contains(.fitsCookingTime),
            "A stated provider time should earn the same ranking credit a bundled recipe's would"
        )
    }

    // MARK: - Dietary compliance stays unknown

    func test_savedOnlineRecipe_hasNoDietaryLabels() throws {
        // The provider said "gluten free" and "vegan". FridgeFit records
        // neither: a provider claim is not an assessment.
        let recipe = try SaveOnlineRecipeUseCase.recipe(from: onlineRecipe())

        XCTAssertNil(recipe.dietaryLabels, "A provider diet string must not become a FridgeFit dietary label")
        XCTAssertEqual(recipe.dietaryCompliance(with: [.vegan]), .unknown)
        XCTAssertFalse(recipe.dietaryCompliance(with: [.vegan]).isSafeToRecommend)
    }

    func test_savedOnlineRecipe_isWithheldWhenADietaryRestrictionIsSelected() async throws {
        let saved = InMemorySavedRecipeRepository()
        try await SaveOnlineRecipeUseCase(repository: saved).execute(onlineRecipe())

        let catalogue = CompositeRecipeRepository(
            bundled: InMemoryRecipeRepository(recipes: [
                Fixture.recipe(title: "Labelled Vegan Bundled", dietaryLabels: [.vegan]),
            ]),
            savedRecipes: saved
        )
        let useCase = GenerateContextAwareRecommendationsUseCase(
            recipeRepository: catalogue,
            pantryRepository: InMemoryPantryRepository(seedItems: Fixture.stockedPantry)
        )

        let context = CookingContext(dietaryRestrictions: [.vegan])
        let recommendations = try await useCase.execute(context: context, now: Fixture.now)
        let titles = recommendations.map(\.suitability.recipe.title)

        XCTAssertFalse(
            titles.contains("Online Tomato Pasta"),
            "Unknown dietary compliance must exclude, exactly as it does for an unlabelled bundled recipe"
        )
        XCTAssertTrue(titles.contains("Labelled Vegan Bundled"))
    }

    func test_provenanceGradeRestrictionIsStillRefusedWithSavedRecipesPresent() async throws {
        // main refuses a gluten-free context before reading any data. Adding
        // online recipes must not create a back door into that claim.
        let saved = InMemorySavedRecipeRepository()
        try await SaveOnlineRecipeUseCase(repository: saved).execute(onlineRecipe())

        let useCase = GenerateContextAwareRecommendationsUseCase(
            recipeRepository: CompositeRecipeRepository(
                bundled: InMemoryRecipeRepository(recipes: []),
                savedRecipes: saved
            ),
            pantryRepository: InMemoryPantryRepository(seedItems: Fixture.stockedPantry)
        )

        do {
            _ = try await useCase.execute(
                context: CookingContext(dietaryRestrictions: [.glutenFree]),
                now: Fixture.now
            )
            XCTFail("Expected the generator to refuse an unassessable restriction")
        } catch let error as RecommendationGenerationError {
            guard case .dietaryRestrictionNotAssessable(let unassessable) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(unassessable, [.glutenFree])
        }
    }

    // MARK: - Unknown units never become verified quantities

    func test_unknownUnit_isNeverReportedAsAvailable() async throws {
        // "cloves" has no MeasurementUnit, so the mapper returns nil and the
        // save maps it to pieces. The pantry stores garlic in grams, which
        // does not convert to pieces - so the engine must say unverified,
        // never available, however well the names match.
        let online = onlineRecipe(
            id: 9001,
            title: "Garlic Everything",
            ingredients: [
                OnlineRecipeIngredient(providerID: 11215, name: "Garlic", amount: 5, unit: nil, originalUnit: "cloves"),
            ]
        )
        let recipe = try SaveOnlineRecipeUseCase.recipe(from: online)

        let pantry = [Fixture.pantryItem("Garlic", 200, .grams)]
        let feasibility = EvaluateRecipeFeasibilityUseCase.evaluate(recipe: recipe, against: pantry)
        let evaluation = try XCTUnwrap(feasibility.evaluatedIngredients.first)

        XCTAssertEqual(evaluation.recipeIngredient.unit, .pieces)
        XCTAssertEqual(
            evaluation.availability,
            .quantityUnverified,
            "A name match with unconvertible units must never be read as available"
        )
        XCTAssertNotEqual(evaluation.availability, .available)
    }

    func test_unknownUnitRecipe_isNotReadyToCook() async throws {
        let online = onlineRecipe(
            id: 9002,
            title: "Unverifiable Garlic",
            ingredients: [
                OnlineRecipeIngredient(providerID: 11215, name: "Garlic", amount: 5, unit: nil, originalUnit: "cloves"),
            ]
        )
        let recipe = try SaveOnlineRecipeUseCase.recipe(from: online)
        let pantry = [Fixture.pantryItem("Garlic", 200, .grams)]

        let feasibility = EvaluateRecipeFeasibilityUseCase.evaluate(recipe: recipe, against: pantry)

        XCTAssertNotEqual(
            feasibility.status,
            .makeable,
            "A recipe whose only essential ingredient is unverified must not read as makeable"
        )
    }

    func test_seasoningLinesBecomeOptional_soTheyCannotBlockADish() throws {
        let online = onlineRecipe(
            id: 9003,
            ingredients: [
                OnlineRecipeIngredient(providerID: 1, name: "Pasta", amount: 200, unit: .grams, originalUnit: "g"),
                OnlineRecipeIngredient(providerID: 2, name: "Salt", amount: 0, unit: nil, originalUnit: "pinch"),
            ]
        )
        let recipe = try SaveOnlineRecipeUseCase.recipe(from: online)

        let salt = try XCTUnwrap(recipe.ingredients.first { $0.ingredient.name == "Salt" })
        XCTAssertEqual(salt.role, .optional)

        // Pasta is in the pantry; salt is not, but it is optional.
        let feasibility = EvaluateRecipeFeasibilityUseCase.evaluate(
            recipe: recipe,
            against: [Fixture.pantryItem("Pasta", 500, .grams)]
        )
        XCTAssertEqual(feasibility.status, .makeable)
    }

    func test_uncertainQuantityUnit_becomesOptional() throws {
        // Spoonacular reports "servings" as a unit. It is not a piece count,
        // and must not be summed as one.
        let online = onlineRecipe(
            id: 9004,
            ingredients: [
                OnlineRecipeIngredient(
                    providerID: 1,
                    name: "Spring Onions",
                    amount: 4,
                    unit: .pieces,
                    originalUnit: "servings",
                    quantityIsUncertain: true
                ),
            ]
        )
        let recipe = try SaveOnlineRecipeUseCase.recipe(from: online)

        XCTAssertEqual(recipe.ingredients.first?.role, .optional)
    }

    // MARK: - Session feedback keeps working on saved identities

    func test_sessionFeedbackCanSkipASavedOnlineRecipe() async throws {
        let saved = InMemorySavedRecipeRepository()
        let savedRecipe = try await SaveOnlineRecipeUseCase(repository: saved).execute(onlineRecipe())

        let catalogue = CompositeRecipeRepository(
            bundled: InMemoryRecipeRepository(recipes: [Fixture.recipe(title: "Bundled Pasta")]),
            savedRecipes: saved
        )
        let useCase = GenerateContextAwareRecommendationsUseCase(
            recipeRepository: catalogue,
            pantryRepository: InMemoryPantryRepository(seedItems: Fixture.stockedPantry)
        )

        var session = RecommendationSession()
        session.record(SessionRecipeFeedback(recipeID: savedRecipe.id, action: .skipped))

        let recommendations = try await useCase.execute(
            context: .unrestricted,
            session: session,
            now: Fixture.now
        )

        XCTAssertFalse(
            recommendations.map(\.suitability.recipe.title).contains("Online Tomato Pasta"),
            "A deterministic saved-recipe id must be skippable like any other"
        )
    }

    func test_savedRecipeIDIsStableForTheSameProviderRecipe() {
        let first = SaveOnlineRecipeUseCase.savedRecipeID(forOnlineRecipeID: 716429)
        let second = SaveOnlineRecipeUseCase.savedRecipeID(forOnlineRecipeID: 716429)
        let other = SaveOnlineRecipeUseCase.savedRecipeID(forOnlineRecipeID: 716430)

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, other)
    }
}
