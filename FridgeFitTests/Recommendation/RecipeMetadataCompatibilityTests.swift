//
//  RecipeMetadataCompatibilityTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// Guards the promise that extending `Recipe` broke nothing.
///
/// `Recipe` is `Codable`, so the decode tests below are the real contract:
/// if the new fields were ever made non-optional, or given a custom
/// decoder that required them, every one of these would fail - which is
/// exactly what should happen.
final class RecipeMetadataCompatibilityTests: XCTestCase {

    private typealias Fixture = RecommendationFixture

    // MARK: - Legacy decoding

    /// JSON written before the recommendation metadata existed. Not one of
    /// the five new keys is present.
    private let legacyJSON = """
    {
      "id": "6B29FC40-CA47-1067-B31D-00DD010662DA",
      "title": "Legacy Pasta",
      "summary": "Written before recommendations existed.",
      "servings": 2,
      "ingredients": [
        {
          "id": "6B29FC40-CA47-1067-B31D-00DD010662DB",
          "ingredient": {
            "id": "6B29FC40-CA47-1067-B31D-00DD010662DC",
            "name": "Pasta",
            "category": "Grain"
          },
          "quantity": 250,
          "unit": "g",
          "role": "essential"
        }
      ],
      "instructions": ["Boil it."],
      "symbolName": "fork.knife"
    }
    """

    func testLegacyRecipeJSONStillDecodes() throws {
        let recipe = try JSONDecoder().decode(Recipe.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(recipe.title, "Legacy Pasta")
        XCTAssertEqual(recipe.servings, 2)
        XCTAssertEqual(recipe.ingredients.count, 1)
        XCTAssertEqual(recipe.instructions, ["Boil it."])

        // Every new field absent, none defaulted to a claim.
        XCTAssertNil(recipe.cuisine)
        XCTAssertNil(recipe.tastePreferences)
        XCTAssertNil(recipe.dietaryLabels)
        XCTAssertNil(recipe.totalCookingTimeInMinutes)
        XCTAssertNil(recipe.difficulty)
        XCTAssertFalse(recipe.hasRecommendationMetadata)
    }

    func testLegacyRecipeStillEvaluatesForFeasibilityUnchanged() throws {
        let recipe = try JSONDecoder().decode(Recipe.self, from: Data(legacyJSON.utf8))
        let pantry = [Fixture.pantryItem("Pasta", 500, .grams)]

        let feasibility = EvaluateRecipeFeasibilityUseCase.evaluate(recipe: recipe, against: pantry)

        XCTAssertEqual(feasibility.status, .makeable)
        XCTAssertEqual(feasibility.coveragePercentage, 100)
    }

    func testRecipeRoundTripsThroughCodableWithMetadata() throws {
        let original = Fixture.recipe(
            title: "Full Metadata",
            cuisine: .mexican,
            tastes: [.spicy, .hearty],
            dietaryLabels: [.vegan, .glutenFree],
            minutes: 45,
            difficulty: .moderate
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Recipe.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.cuisine, .mexican)
        XCTAssertEqual(decoded.tastePreferences, [.spicy, .hearty])
        XCTAssertEqual(decoded.dietaryLabels, [.vegan, .glutenFree])
        XCTAssertEqual(decoded.totalCookingTimeInMinutes, 45)
        XCTAssertEqual(decoded.difficulty, .moderate)
    }

    // MARK: - Existing initializer compatibility

    /// The original call signature must still compile and still produce a
    /// usable recipe. If a required parameter were ever added, this stops
    /// building.
    func testOriginalInitializerSignatureStillWorks() {
        let recipe = Recipe(
            title: "Old Call Site",
            summary: "No metadata passed.",
            servings: 1,
            ingredients: [Fixture.essential("Eggs", 2, .pieces)],
            instructions: ["Scramble."],
            symbolName: "circle"
        )

        XCTAssertEqual(recipe.title, "Old Call Site")
        XCTAssertNil(recipe.cuisine)
        XCTAssertNil(recipe.difficulty)
    }

    // MARK: - Absence semantics

    func testEmptyDietaryLabelsIsAssessedAndDistinctFromNil() {
        let assessed = Fixture.recipe(title: "Assessed", dietaryLabels: [])
        let unassessed = Fixture.recipe(title: "Unassessed", dietaryLabels: nil)

        XCTAssertEqual(
            assessed.dietaryCompliance(with: [.vegan]),
            .violated(missing: [.vegan])
        )
        XCTAssertEqual(unassessed.dietaryCompliance(with: [.vegan]), .unknown)
    }

    func testNoRestrictionsIsAlwaysSatisfiedEvenWhenUnassessed() {
        let unassessed = Fixture.recipe(title: "Unassessed", dietaryLabels: nil)
        XCTAssertEqual(unassessed.dietaryCompliance(with: []), .satisfied)
    }

    func testUnstatedMetadataReturnsNilRatherThanFalse() {
        let legacy = Fixture.legacyRecipe()

        XCTAssertNil(legacy.fitsCookingTime(within: .fifteenMinutes))
        XCTAssertNil(legacy.fitsDifficulty(atMost: .easy))
        XCTAssertFalse(legacy.matchesCuisine(in: [.italian]))
        XCTAssertFalse(legacy.matchesTaste(in: [.savoury]))
    }

    func testStatedMetadataComparesCorrectly() {
        let recipe = Fixture.recipe(
            title: "Stated",
            cuisine: .asian,
            tastes: [.spicy],
            minutes: 30,
            difficulty: .moderate
        )

        XCTAssertEqual(recipe.fitsCookingTime(within: .thirtyMinutes), true)
        XCTAssertEqual(recipe.fitsCookingTime(within: .fifteenMinutes), false)
        XCTAssertEqual(recipe.fitsDifficulty(atMost: .moderate), true)
        XCTAssertEqual(recipe.fitsDifficulty(atMost: .easy), false)
        XCTAssertTrue(recipe.matchesCuisine(in: [.asian, .italian]))
        XCTAssertFalse(recipe.matchesCuisine(in: [.italian]))
        XCTAssertTrue(recipe.matchesTaste(in: [.spicy]))
        XCTAssertFalse(recipe.matchesTaste(in: [.mild]))
    }

    func testEmptyPreferenceSetsNeverMatch() {
        let recipe = Fixture.recipe(title: "Stated", cuisine: .asian, tastes: [.spicy])

        XCTAssertFalse(recipe.matchesCuisine(in: []))
        XCTAssertFalse(recipe.matchesTaste(in: []))
    }

    // MARK: - Bundled catalogue integrity

    func testEveryBundledRecipeStatesTimeDifficultyAndCuisine() async throws {
        let recipes = try await BundledRecipeRepository().fetchAll()

        XCTAssertEqual(recipes.count, 10)
        for recipe in recipes {
            XCTAssertNotNil(recipe.cuisine, "\(recipe.title) has no cuisine.")
            XCTAssertNotNil(recipe.difficulty, "\(recipe.title) has no difficulty.")
            XCTAssertNotNil(recipe.dietaryLabels, "\(recipe.title) was never assessed.")
            guard let minutes = recipe.totalCookingTimeInMinutes else {
                return XCTFail("\(recipe.title) has no cooking time.")
            }
            XCTAssertGreaterThan(minutes, 0)
            XCTAssertFalse(recipe.tastePreferences?.isEmpty ?? true, "\(recipe.title) has no tastes.")
            XCTAssertTrue(recipe.hasRecommendationMetadata)
        }
    }

    /// The release audit, pinned.
    ///
    /// Each expected set below was checked by hand against that recipe's
    /// own ingredient list, optional ingredients included. Changing a
    /// bundled recipe's dietary labels must mean changing this table too,
    /// which is the point: a label is a claim about what someone can
    /// safely eat, and it should not be possible to adjust one quietly.
    func testBundledDietaryLabelsMatchTheAudit() async throws {
        let expected: [String: Set<DietaryRestriction>] = [
            // Chicken, cream, wheat pasta.
            "Creamy Chicken Pasta": [],
            // Egg rules out vegan; nothing dairy.
            "Vegetable Fried Rice": [.vegetarian, .dairyFree],
            // Milk, cheddar, butter.
            "Classic Cheese Omelette": [.vegetarian],
            // Beef, cheddar, wheat tortilla.
            "Beef Tacos": [],
            // Optional cream still counts against dairy free and vegan.
            "Tomato Soup": [.vegetarian],
            // Milk, egg, butter.
            "Banana Pancakes": [.vegetarian],
            // Cheddar and butter.
            "Grilled Cheese Sandwich": [.vegetarian],
            // Chicken, parmesan, and a dressing conventionally containing
            // anchovy and egg.
            "Chicken Caesar Salad": [],
            // No animal product at all, optional cumin included.
            "Rice and Beans": [.vegetarian, .vegan, .dairyFree],
            // Yogurt rules out dairy free; honey also rules out vegan.
            "Greek Yogurt Parfait": [.vegetarian],
        ]

        let recipes = try await BundledRecipeRepository().fetchAll()
        XCTAssertEqual(recipes.count, expected.count)

        for recipe in recipes {
            guard let expectedLabels = expected[recipe.title] else {
                XCTFail("\(recipe.title) is not covered by the dietary audit.")
                continue
            }
            XCTAssertEqual(
                recipe.dietaryLabels,
                expectedLabels,
                "\(recipe.title) labels drifted from the audited set."
            )
        }
    }

    /// The bundled labels must not contradict the bundled ingredients.
    /// This is the check that would catch someone labelling a dish vegan
    /// while it still lists cream.
    func testBundledDietaryLabelsDoNotContradictIngredients() async throws {
        let recipes = try await BundledRecipeRepository().fetchAll()

        for recipe in recipes {
            let labels = recipe.dietaryLabels ?? []
            let categories = Set(recipe.ingredients.map(\.ingredient.category))
            let names = recipe.ingredients.map { $0.ingredient.name.lowercased() }

            if labels.contains(.vegetarian) {
                XCTAssertFalse(
                    categories.contains(.meat),
                    "\(recipe.title) is labelled vegetarian but lists a meat ingredient."
                )
            }

            if labels.contains(.vegan) {
                XCTAssertFalse(
                    categories.contains(.meat) || categories.contains(.dairy),
                    "\(recipe.title) is labelled vegan but lists meat or dairy."
                )
                XCTAssertFalse(
                    names.contains(where: { $0.contains("egg") || $0.contains("honey") }),
                    "\(recipe.title) is labelled vegan but lists eggs or honey."
                )
            }

            if labels.contains(.dairyFree) {
                XCTAssertFalse(
                    categories.contains(.dairy),
                    "\(recipe.title) is labelled dairy free but lists a dairy ingredient."
                )
            }

            // The inverse direction: a dish that clearly *does* contain an
            // animal product must not be missing from that exclusion.
            if categories.contains(.meat) {
                XCTAssertFalse(
                    labels.contains(.vegetarian) || labels.contains(.vegan),
                    "\(recipe.title) lists meat but claims a meat-free label."
                )
            }
            if categories.contains(.dairy) {
                XCTAssertFalse(
                    labels.contains(.dairyFree) || labels.contains(.vegan),
                    "\(recipe.title) lists dairy but claims a dairy-free label."
                )
            }
        }
    }
}
