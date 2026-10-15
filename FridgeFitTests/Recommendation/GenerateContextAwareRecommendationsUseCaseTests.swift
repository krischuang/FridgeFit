//
//  GenerateContextAwareRecommendationsUseCaseTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// Covers generation, ranking order, determinism, and the failure cases.
final class GenerateContextAwareRecommendationsUseCaseTests: XCTestCase {

    private typealias Fixture = RecommendationFixture

    // MARK: - Failure cases

    func testEmptyPantryThrowsPantryNeedsIngredients() async {
        await assertThrows(.pantryNeedsIngredients) {
            try await Fixture.recommendations(
                recipes: [Fixture.recipe(title: "Anything")],
                pantry: []
            )
        }
    }

    func testEmptyRecipeCatalogueThrowsCatalogueEmpty() async {
        await assertThrows(.recipeCatalogueEmpty) {
            try await Fixture.recommendations(
                recipes: [],
                pantry: Fixture.stockedPantry
            )
        }
    }

    func testUnreadablePantryThrowsPantryInformationUnavailable() async {
        let useCase = GenerateContextAwareRecommendationsUseCase(
            recipeRepository: InMemoryRecipeRepository(recipes: [Fixture.recipe(title: "A")]),
            pantryRepository: UnavailablePantryRepository()
        )

        await assertThrows(.pantryInformationUnavailable) {
            try await useCase.execute(context: .unrestricted, now: Fixture.now)
        }
    }

    func testUnreadableCatalogueThrowsCatalogueUnavailable() async {
        let useCase = GenerateContextAwareRecommendationsUseCase(
            recipeRepository: UnavailableRecipeRepository(),
            pantryRepository: InMemoryPantryRepository(seedItems: Fixture.stockedPantry)
        )

        await assertThrows(.recipeCatalogueUnavailable) {
            try await useCase.execute(context: .unrestricted, now: Fixture.now)
        }
    }

    /// A filter the user can relax must be reported as such, so the screen
    /// can offer the preference form rather than blaming the pantry.
    func testPreferenceOnlyExclusionsReportFiltersExcludeFeasibleRecipes() async {
        await assertThrows(.filtersExcludeFeasibleRecipes) {
            try await Fixture.recommendations(
                recipes: [
                    Fixture.recipe(title: "Slow A", minutes: 60),
                    Fixture.recipe(title: "Slow B", minutes: 45),
                ],
                pantry: Fixture.stockedPantry,
                context: CookingContext(maximumCookingTime: .fifteenMinutes)
            )
        }
    }

    func testPantryShortfallReportsNoRealisticallySuitableRecipes() async {
        let recipe = Fixture.recipe(title: "Needs Lots", ingredients: [
            Fixture.essential("A", 1, .pieces),
            Fixture.essential("B", 1, .pieces),
            Fixture.essential("C", 1, .pieces),
            Fixture.essential("D", 1, .pieces),
        ])

        await assertThrows(.noRealisticallySuitableRecipes) {
            try await Fixture.recommendations(
                recipes: [recipe],
                pantry: [Fixture.pantryItem("A", 5, .pieces)]
            )
        }
    }

    /// A restriction FridgeFit cannot assess must fail the run with a
    /// message about the app's limits, not one about the user's filters.
    ///
    /// It fails closed before any data is read: any list returned under a
    /// gluten-free filter would imply a check that was never performed.
    func testUnassessableRestrictionFailsClosedWithItsOwnError() async {
        for restriction in DietaryRestriction.unassessableCases {
            await assertThrows(.dietaryRestrictionNotAssessable([restriction])) {
                try await Fixture.recommendations(
                    recipes: [
                        // Labelled with the restriction anyway - the guard
                        // must not be satisfiable by a label.
                        Fixture.recipe(title: "A", dietaryLabels: [restriction]),
                        Fixture.recipe(title: "B", dietaryLabels: nil),
                    ],
                    pantry: Fixture.stockedPantry,
                    context: CookingContext(dietaryRestrictions: [restriction])
                )
            }
        }
    }

    func testUnassessableRestrictionIsRefusedEvenAlongsideAssessableOnes() async {
        await assertThrows(.dietaryRestrictionNotAssessable([.glutenFree])) {
            try await Fixture.recommendations(
                recipes: [Fixture.recipe(title: "A", dietaryLabels: [.vegan, .glutenFree])],
                pantry: Fixture.stockedPantry,
                context: CookingContext(dietaryRestrictions: [.vegan, .glutenFree])
            )
        }
    }

    /// An assessable restriction that nothing is labelled for is a
    /// different situation: the filter genuinely excluded the options, and
    /// relaxing it is the fix.
    func testAssessableRestrictionWithNoMatchesReportsFilterExclusion() async {
        await assertThrows(.filtersExcludeFeasibleRecipes) {
            try await Fixture.recommendations(
                recipes: [
                    Fixture.recipe(title: "A", dietaryLabels: [.vegetarian]),
                    Fixture.recipe(title: "B", dietaryLabels: nil),
                ],
                pantry: Fixture.stockedPantry,
                context: CookingContext(dietaryRestrictions: [.vegan])
            )
        }
    }

    func testConflictingPreferencesYieldFilterExclusionNotACrash() async {
        await assertThrows(.filtersExcludeFeasibleRecipes) {
            try await Fixture.recommendations(
                recipes: [Fixture.recipe(title: "Slow Hard", minutes: 60, difficulty: .challenging)],
                pantry: Fixture.stockedPantry,
                context: CookingContext(
                    maximumCookingTime: .fifteenMinutes,
                    maximumDifficulty: .easy,
                    preferredCuisines: [.mexican],
                    dietaryRestrictions: [.vegan]
                )
            )
        }
    }

    // MARK: - Legacy recipes

    /// A catalogue of nothing but metadata-free recipes must still produce
    /// recommendations in the default context. This is the "always nil
    /// metadata plus filters that exclude everything" failure the
    /// integration was explicitly required to avoid.
    func testLegacyRecipesWithoutMetadataStillGetRecommended() async throws {
        let recommendations = try await Fixture.recommendations(
            recipes: [
                Fixture.legacyRecipe(title: "Legacy A"),
                Fixture.legacyRecipe(title: "Legacy B"),
            ],
            pantry: Fixture.stockedPantry
        )

        XCTAssertEqual(recommendations.count, 2)
        XCTAssertTrue(recommendations.allSatisfy { $0.readiness == .readyToCook })
    }

    func testLegacyRecipesSurviveTimeAndDifficultyLimits() async throws {
        let recommendations = try await Fixture.recommendations(
            recipes: [Fixture.legacyRecipe(title: "Legacy")],
            pantry: Fixture.stockedPantry,
            context: CookingContext(
                maximumCookingTime: .fifteenMinutes,
                maximumDifficulty: .easy
            )
        )

        XCTAssertEqual(recommendations.count, 1)
    }

    func testMissingCuisineEarnsNoCuisineReasonButIsStillOffered() async throws {
        let recommendations = try await Fixture.recommendations(
            recipes: [Fixture.recipe(title: "No Cuisine", cuisine: nil)],
            pantry: Fixture.stockedPantry,
            context: CookingContext(preferredCuisines: [.italian])
        )

        XCTAssertEqual(recommendations.count, 1)
        XCTAssertFalse(recommendations[0].rankingReasons.contains(.matchesCuisinePreference))
    }

    // MARK: - Ranking

    func testReadyToCookOutranksNeedsShopping() async throws {
        let ready = Fixture.recipe(title: "Ready", ingredients: [
            Fixture.essential("Pasta", 100, .grams),
        ])
        let needsOne = Fixture.recipe(title: "Needs One", ingredients: [
            Fixture.essential("Pasta", 100, .grams),
            Fixture.essential("Capers", 10, .grams),
        ])

        let recommendations = try await Fixture.recommendations(
            recipes: [needsOne, ready],
            pantry: [Fixture.pantryItem("Pasta", 500, .grams)]
        )

        XCTAssertEqual(recommendations.map(\.recipe.title), ["Ready", "Needs One"])
    }

    func testPreferredCuisineOutranksUnpreferredWhenOtherwiseEqual() async throws {
        let recommendations = try await Fixture.recommendations(
            recipes: [
                Fixture.recipe(title: "Asian Dish", cuisine: .asian),
                Fixture.recipe(title: "Italian Dish", cuisine: .italian),
            ],
            pantry: Fixture.stockedPantry,
            context: CookingContext(preferredCuisines: [.asian])
        )

        XCTAssertEqual(recommendations.first?.recipe.title, "Asian Dish")
        XCTAssertTrue(recommendations[0].rankingReasons.contains(.matchesCuisinePreference))
    }

    func testPreferredTasteBreaksTieWhenCuisineIsEqual() async throws {
        let recommendations = try await Fixture.recommendations(
            recipes: [
                Fixture.recipe(title: "Mild One", tastes: [.mild]),
                Fixture.recipe(title: "Spicy One", tastes: [.spicy]),
            ],
            pantry: Fixture.stockedPantry,
            context: CookingContext(preferredTastes: [.spicy])
        )

        XCTAssertEqual(recommendations.first?.recipe.title, "Spicy One")
    }

    /// The source branch's deliberate inversion, preserved: rescuing food
    /// about to go off is worth one small shop.
    func testUrgentButNotQuiteReadyOutranksReadyWhenExpiryIsPrioritised() async throws {
        let urgentNeedsOne = Fixture.recipe(title: "Rescue", ingredients: [
            Fixture.essential("Spinach", 50, .grams),
            Fixture.essential("Capers", 10, .grams),
        ])
        let ready = Fixture.recipe(title: "Ready", ingredients: [
            Fixture.essential("Pasta", 100, .grams),
        ])

        let pantry = [
            Fixture.pantryItem("Spinach", 300, .grams, expiresInDays: 1),
            Fixture.pantryItem("Pasta", 500, .grams),
        ]

        let prioritised = try await Fixture.recommendations(
            recipes: [ready, urgentNeedsOne],
            pantry: pantry,
            context: CookingContext(prioritisesExpiringIngredients: true)
        )
        XCTAssertEqual(prioritised.map(\.recipe.title), ["Rescue", "Ready"])

        // With the preference off, ordinary readiness wins again.
        let notPrioritised = try await Fixture.recommendations(
            recipes: [ready, urgentNeedsOne],
            pantry: pantry,
            context: CookingContext(prioritisesExpiringIngredients: false)
        )
        XCTAssertEqual(notPrioritised.map(\.recipe.title), ["Ready", "Rescue"])
    }

    /// Expired food sinks regardless of the expiry preference - the engine
    /// must never promote eating something past its date.
    func testRecipeUsingExpiredFoodIsNotPromoted() async throws {
        let expiredDish = Fixture.recipe(title: "Expired Dish", ingredients: [
            Fixture.essential("Spinach", 50, .grams),
        ])
        let freshDish = Fixture.recipe(title: "Fresh Dish", ingredients: [
            Fixture.essential("Pasta", 50, .grams),
        ])
        let pantry = [
            Fixture.pantryItem("Spinach", 300, .grams, expiresInDays: -2),
            Fixture.pantryItem("Pasta", 500, .grams),
        ]

        for prioritises in [true, false] {
            let recommendations = try await Fixture.recommendations(
                recipes: [expiredDish, freshDish],
                pantry: pantry,
                context: CookingContext(prioritisesExpiringIngredients: prioritises)
            )
            XCTAssertEqual(
                recommendations.map(\.recipe.title),
                ["Fresh Dish", "Expired Dish"],
                "Expired food must never be promoted (prioritises=\(prioritises))."
            )
        }
    }

    // MARK: - Determinism

    /// Two recipes identical on every ranking key must still come back in
    /// one fixed order, every run. Without the title/id tiebreak the list
    /// would reshuffle between runs.
    func testOrderingIsDeterministicForOtherwiseIdenticalRecipes() async throws {
        let recipes = (1...6).map { index in
            Fixture.recipe(title: "Dish \(index)")
        }

        var observed: [[String]] = []
        for _ in 0..<5 {
            let recommendations = try await Fixture.recommendations(
                recipes: recipes.shuffled(),
                pantry: Fixture.stockedPantry
            )
            observed.append(recommendations.map(\.recipe.title))
        }

        XCTAssertEqual(
            observed.first,
            ["Dish 1", "Dish 2", "Dish 3", "Dish 4", "Dish 5", "Dish 6"]
        )
        XCTAssertTrue(
            observed.allSatisfy { $0 == observed[0] },
            "Ranking must not depend on input order: \(observed)"
        )
    }

    func testRepeatedRunsWithSameInputsProduceIdenticalOutput() async throws {
        let recipes = [
            Fixture.recipe(title: "Alpha", cuisine: .asian, minutes: 20),
            Fixture.recipe(title: "Beta", cuisine: .italian, minutes: 20),
            Fixture.legacyRecipe(title: "Gamma"),
        ]
        let context = CookingContext(preferredCuisines: [.asian], preferredTastes: [.savoury])

        let first = try await Fixture.recommendations(
            recipes: recipes, pantry: Fixture.stockedPantry, context: context
        )
        let second = try await Fixture.recommendations(
            recipes: recipes, pantry: Fixture.stockedPantry, context: context
        )

        XCTAssertEqual(first.map(\.recipe.title), second.map(\.recipe.title))
        XCTAssertEqual(first.map(\.rankingReasons), second.map(\.rankingReasons))
    }

    // MARK: - Explanations

    func testReadyRecipeExplainsItselfWithEarnedReasonsOnly() async throws {
        let recipe = Fixture.recipe(
            title: "Perfect",
            cuisine: .asian,
            tastes: [.spicy],
            dietaryLabels: [.vegetarian],
            minutes: 20,
            difficulty: .easy,
            ingredients: [Fixture.essential("Pasta", 100, .grams)]
        )

        let recommendations = try await Fixture.recommendations(
            recipes: [recipe],
            pantry: [Fixture.pantryItem("Pasta", 500, .grams)],
            context: CookingContext(
                maximumCookingTime: .thirtyMinutes,
                maximumDifficulty: .moderate,
                preferredCuisines: [.asian],
                preferredTastes: [.spicy],
                dietaryRestrictions: [.vegetarian]
            )
        )

        let reasons = Set(recommendations[0].rankingReasons)
        XCTAssertEqual(reasons, [
            .readyToCook,
            .matchesCuisinePreference,
            .matchesTastePreference,
            .fitsCookingTime,
            .fitsDifficulty,
            .matchesDietaryRestrictions,
            .strongPantryMatch,
        ])
        XCTAssertFalse(reasons.contains(.minimalShopping))
        XCTAssertFalse(reasons.contains(.usesIngredientExpiringSoon))
    }

    func testMinimalShoppingOnlyAppearsWhenExactlyOneThingIsNeeded() async throws {
        let recipe = Fixture.recipe(title: "One Short", ingredients: [
            Fixture.essential("Pasta", 100, .grams),
            Fixture.essential("Capers", 10, .grams),
        ])

        let recommendations = try await Fixture.recommendations(
            recipes: [recipe],
            pantry: [Fixture.pantryItem("Pasta", 500, .grams)]
        )

        XCTAssertTrue(recommendations[0].rankingReasons.contains(.minimalShopping))
        XCTAssertEqual(recommendations[0].suitability.shoppingIngredients, ["Capers"])
    }

    func testDietaryReasonNeverAppearsWithoutASelectedRestriction() async throws {
        let recommendations = try await Fixture.recommendations(
            recipes: [Fixture.recipe(title: "Labelled", dietaryLabels: [.vegan])],
            pantry: Fixture.stockedPantry
        )

        XCTAssertFalse(
            recommendations[0].rankingReasons.contains(.matchesDietaryRestrictions),
            "Nothing was required, so nothing was met."
        )
    }

    // MARK: - Live architecture

    /// The feature must run on main's bundled catalogue and main's pantry
    /// abstraction, not on a ported sample store.
    func testRunsAgainstTheRealBundledCatalogueAndPantryRepository() async throws {
        let pantry = InMemoryPantryRepository(seedItems: [
            Fixture.pantryItem("Rice", 600, .grams),
            Fixture.pantryItem("Black Beans", 500, .grams),
            Fixture.pantryItem("Onion", 3, .pieces),
            Fixture.pantryItem("Garlic", 4, .pieces),
        ])
        let useCase = GenerateContextAwareRecommendationsUseCase(
            recipeRepository: BundledRecipeRepository(),
            pantryRepository: pantry
        )

        let recommendations = try await useCase.execute(context: .unrestricted, now: Fixture.now)

        XCTAssertFalse(recommendations.isEmpty)
        XCTAssertEqual(recommendations.first?.recipe.title, "Rice and Beans")
        XCTAssertEqual(recommendations.first?.readiness, .readyToCook)
    }

    /// Every restriction the form actually offers must be satisfiable by
    /// at least one bundled recipe, or it is a filter that silently
    /// returns nothing.
    func testEveryOfferedRestrictionIsSatisfiableByABundledRecipe() async throws {
        let recipes = try await BundledRecipeRepository().fetchAll()

        for restriction in DietaryRestriction.assessableCases {
            let matching = recipes.filter { $0.dietaryLabels?.contains(restriction) == true }
            XCTAssertFalse(
                matching.isEmpty,
                "No bundled recipe is labelled \(restriction.rawValue), so that filter can never return anything."
            )
        }
    }

    /// The safety invariant: FridgeFit must not publish an allergen-grade
    /// claim it has no product data to support.
    ///
    /// This is the test that would have caught the gluten-free labels on
    /// the cheese omelette and the rice and beans.
    func testNoBundledRecipeClaimsAnAllergenGradeRestriction() async throws {
        let recipes = try await BundledRecipeRepository().fetchAll()

        for restriction in DietaryRestriction.unassessableCases {
            let offenders = recipes
                .filter { $0.dietaryLabels?.contains(restriction) == true }
                .map(\.title)

            XCTAssertTrue(
                offenders.isEmpty,
                "\(restriction.rawValue) depends on product provenance this dataset does not have, but it is claimed by: \(offenders.joined(separator: ", "))."
            )
        }
    }

    func testAllergenGradeRestrictionsAreNotOfferedAsFilters() {
        XCTAssertEqual(Set(DietaryRestriction.unassessableCases), [.glutenFree, .nutFree])
        XCTAssertEqual(Set(DietaryRestriction.assessableCases), [.vegetarian, .vegan, .dairyFree])
        XCTAssertEqual(
            Set(DietaryRestriction.allCases),
            Set(DietaryRestriction.assessableCases)
                .union(DietaryRestriction.unassessableCases),
            "Every restriction must be classified one way or the other."
        )

        for restriction in DietaryRestriction.unassessableCases {
            XCTAssertNotNil(
                restriction.unassessableExplanation,
                "\(restriction.rawValue) is withheld, so the UI needs a reason to show."
            )
        }
        for restriction in DietaryRestriction.assessableCases {
            XCTAssertNil(restriction.unassessableExplanation)
        }
    }

    // MARK: - Helpers

    private func assertThrows(
        _ expected: RecommendationGenerationError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> [RecipeRecommendation]
    ) async {
        do {
            let result = try await body()
            XCTFail("Expected \(expected), got \(result.count) recommendations.", file: file, line: line)
        } catch let error as RecommendationGenerationError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected \(expected), got \(error).", file: file, line: line)
        }
    }
}
