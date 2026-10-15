//
//  EvaluateRecipeSuitabilityUseCaseTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// Covers the context filters, the readiness reading of main's feasibility
/// verdict, and the expiry rules.
///
/// The quantity cases here are the point of the whole integration: the
/// branch this came from matched ingredient names, so a pantry holding a
/// trace of something counted as having it. Every assertion below that
/// mentions an amount would have passed wrongly under that rule.
final class EvaluateRecipeSuitabilityUseCaseTests: XCTestCase {

    private typealias Fixture = RecommendationFixture

    // MARK: - Quantity semantics (regression-critical)

    func testInsufficientQuantityIsNotReadyToCook() {
        let recipe = Fixture.recipe(title: "Pasta", ingredients: [
            Fixture.essential("Pasta", 200, .grams),
        ])
        // Has the ingredient, but only a tenth of what's needed.
        let pantry = [Fixture.pantryItem("Pasta", 20, .grams)]

        let suitability = Fixture.suitability(of: recipe, pantry: pantry).suitable

        XCTAssertEqual(suitability?.readiness, .needsOneToTwoIngredients)
        XCTAssertEqual(suitability?.shoppingIngredients, ["Pasta"])
        XCTAssertEqual(suitability?.pantryMatchPercentage, 0)
    }

    func testSufficientQuantityAcrossConvertibleUnitsIsReadyToCook() {
        let recipe = Fixture.recipe(title: "Pasta", ingredients: [
            Fixture.essential("Pasta", 200, .grams),
        ])
        // 1 kg converts to 1000 g, which covers 200 g.
        let pantry = [Fixture.pantryItem("Pasta", 1, .kilograms)]

        let suitability = Fixture.suitability(of: recipe, pantry: pantry).suitable

        XCTAssertEqual(suitability?.readiness, .readyToCook)
        XCTAssertTrue(suitability?.shoppingIngredients.isEmpty == true)
        XCTAssertEqual(suitability?.pantryMatchPercentage, 100)
    }

    func testIncompatibleUnitsAreUnverifiedNotAvailable() {
        let recipe = Fixture.recipe(title: "Soup", ingredients: [
            Fixture.essential("Stock", 500, .milliliters),
        ])
        // Grams to millilitres is not a safe conversion.
        let pantry = [Fixture.pantryItem("Stock", 900, .grams)]

        let suitability = Fixture.suitability(of: recipe, pantry: pantry).suitable

        XCTAssertEqual(suitability?.readiness, .almostReady)
        XCTAssertEqual(suitability?.unverifiedIngredients, ["Stock"])
        XCTAssertTrue(suitability?.shoppingIngredients.isEmpty == true)
        // Never counted as covered.
        XCTAssertEqual(suitability?.pantryMatchPercentage, 0)
    }

    func testUnverifiedQuantityDoesNotEarnReadyToCookReason() {
        let recipe = Fixture.recipe(title: "Soup", ingredients: [
            Fixture.essential("Stock", 500, .milliliters),
        ])
        let pantry = [Fixture.pantryItem("Stock", 900, .grams)]

        guard let suitability = Fixture.suitability(of: recipe, pantry: pantry).suitable else {
            return XCTFail("Expected a suitable recipe.")
        }
        let reasons = GenerateContextAwareRecommendationsUseCase.rankingReasons(
            for: suitability,
            context: .unrestricted
        )

        XCTAssertFalse(reasons.contains(.readyToCook))
        XCTAssertFalse(reasons.contains(.strongPantryMatch))
    }

    func testMoreThanTwoMissingEssentialsIsExcluded() {
        let recipe = Fixture.recipe(title: "Big Dish", ingredients: [
            Fixture.essential("A", 1, .pieces),
            Fixture.essential("B", 1, .pieces),
            Fixture.essential("C", 1, .pieces),
            Fixture.essential("D", 1, .pieces),
        ])
        let pantry = [Fixture.pantryItem("A", 5, .pieces)]

        XCTAssertEqual(
            Fixture.suitability(of: recipe, pantry: pantry).exclusion,
            .requiresMoreThanTwoIngredients
        )
    }

    func testOptionalIngredientsNeverBlockReadiness() {
        let recipe = Fixture.recipe(title: "Garnished", ingredients: [
            Fixture.essential("Pasta", 100, .grams),
            Fixture.optional("Parsley", 5, .grams),
            Fixture.optional("Basil", 5, .grams),
            Fixture.optional("Chilli", 5, .grams),
        ])
        let pantry = [Fixture.pantryItem("Pasta", 500, .grams)]

        let suitability = Fixture.suitability(of: recipe, pantry: pantry).suitable
        XCTAssertEqual(suitability?.readiness, .readyToCook)
    }

    // MARK: - Dietary restrictions

    func testUnknownDietaryComplianceIsWithheldNotAssumedSafe() {
        let recipe = Fixture.recipe(title: "Unlabelled", dietaryLabels: nil)
        let context = CookingContext(dietaryRestrictions: [.vegan])

        XCTAssertEqual(
            Fixture.suitability(of: recipe, pantry: Fixture.stockedPantry, context: context).exclusion,
            .dietaryComplianceUnknown
        )
        XCTAssertFalse(DietaryCompliance.unknown.isSafeToRecommend)
    }

    /// The compliance rule itself is restriction-agnostic - it fails
    /// closed for every restriction, including the ones the form doesn't
    /// offer. The generator refuses those earlier (see
    /// `GenerateContextAwareRecommendationsUseCaseTests`); this is the
    /// second layer.
    func testUnknownComplianceFailsClosedForEveryRestriction() {
        let unlabelled = Fixture.recipe(title: "Unlabelled", dietaryLabels: nil)

        for restriction in DietaryRestriction.allCases {
            XCTAssertEqual(
                unlabelled.dietaryCompliance(with: [restriction]),
                .unknown,
                "\(restriction.rawValue) must not be assumed from absent labels."
            )
            XCTAssertEqual(
                Fixture.suitability(
                    of: unlabelled,
                    pantry: Fixture.stockedPantry,
                    context: CookingContext(dietaryRestrictions: [restriction])
                ).exclusion,
                .dietaryComplianceUnknown
            )
        }
    }

    func testAssessedButNonCompliantRecipeReportsWhichRestrictionIsMissing() {
        let recipe = Fixture.recipe(title: "Cheesy", dietaryLabels: [.vegetarian])
        let context = CookingContext(dietaryRestrictions: [.vegetarian, .vegan])

        XCTAssertEqual(
            Fixture.suitability(of: recipe, pantry: Fixture.stockedPantry, context: context).exclusion,
            .dietaryRestrictionConflict(missing: [.vegan])
        )
    }

    func testCompliantRecipePasses() {
        let recipe = Fixture.recipe(title: "Beans", dietaryLabels: [.vegetarian, .vegan])
        let context = CookingContext(dietaryRestrictions: [.vegan])

        let suitability = Fixture.suitability(
            of: recipe,
            pantry: Fixture.stockedPantry,
            context: context
        ).suitable

        XCTAssertEqual(suitability?.dietaryCompliance, .satisfied)
    }

    func testNoSelectedRestrictionsLetsUnlabelledRecipesThrough() {
        let recipe = Fixture.recipe(title: "Unlabelled", dietaryLabels: nil)

        XCTAssertNotNil(
            Fixture.suitability(of: recipe, pantry: Fixture.stockedPantry).suitable
        )
    }

    // MARK: - Time and difficulty

    func testCookingTimeOverLimitIsExcluded() {
        let recipe = Fixture.recipe(title: "Slow", minutes: 60)
        let context = CookingContext(maximumCookingTime: .thirtyMinutes)

        XCTAssertEqual(
            Fixture.suitability(of: recipe, pantry: Fixture.stockedPantry, context: context).exclusion,
            .cookingTimeExceedsLimit
        )
    }

    func testDifficultyOverLimitIsExcluded() {
        let recipe = Fixture.recipe(title: "Hard", difficulty: .challenging)
        let context = CookingContext(maximumDifficulty: .easy)

        XCTAssertEqual(
            Fixture.suitability(of: recipe, pantry: Fixture.stockedPantry, context: context).exclusion,
            .difficultyExceedsLimit
        )
    }

    /// The deliberate asymmetry with dietary metadata: unstated time is a
    /// preference, not a safety question, so the recipe is still offered
    /// rather than filtered out.
    func testUnstatedTimeAndDifficultyAreNotExcludedByLimits() {
        let recipe = Fixture.recipe(title: "Unstated", minutes: nil, difficulty: nil)
        let context = CookingContext(
            maximumCookingTime: .fifteenMinutes,
            maximumDifficulty: .easy
        )

        let suitability = Fixture.suitability(
            of: recipe,
            pantry: Fixture.stockedPantry,
            context: context
        ).suitable

        XCTAssertNotNil(suitability, "Unstated metadata must not exclude a recipe.")
    }

    func testUnstatedTimeAndDifficultyEarnNoRankingCredit() {
        let recipe = Fixture.recipe(title: "Unstated", minutes: nil, difficulty: nil)
        guard let suitability = Fixture.suitability(
            of: recipe,
            pantry: Fixture.stockedPantry
        ).suitable else {
            return XCTFail("Expected a suitable recipe.")
        }

        let reasons = GenerateContextAwareRecommendationsUseCase.rankingReasons(
            for: suitability,
            context: .unrestricted
        )

        XCTAssertFalse(reasons.contains(.fitsCookingTime))
        XCTAssertFalse(reasons.contains(.fitsDifficulty))
    }

    // MARK: - Expiry

    func testIngredientExpiringSoonIsMarkedUrgent() {
        let recipe = Fixture.recipe(title: "Use It", ingredients: [
            Fixture.essential("Spinach", 100, .grams),
        ])
        let pantry = [Fixture.pantryItem("Spinach", 300, .grams, expiresInDays: 1)]

        let suitability = Fixture.suitability(of: recipe, pantry: pantry).suitable

        XCTAssertEqual(suitability?.usesUrgentIngredient, true)
        XCTAssertEqual(suitability?.urgentIngredients.first?.ingredientName, "Spinach")
        XCTAssertEqual(suitability?.urgentIngredients.first?.urgency, .tomorrow)
        XCTAssertEqual(suitability?.urgentIngredients.first?.daysUntilExpiry, 1)
    }

    /// Already-expired food must never read as a reason to cook.
    func testExpiredIngredientIsNeverUrgentAndIsReportedSeparately() {
        let recipe = Fixture.recipe(title: "Risky", ingredients: [
            Fixture.essential("Spinach", 100, .grams),
        ])
        let pantry = [Fixture.pantryItem("Spinach", 300, .grams, expiresInDays: -3)]

        guard let suitability = Fixture.suitability(of: recipe, pantry: pantry).suitable else {
            return XCTFail("Expected a suitable recipe.")
        }

        XCTAssertFalse(suitability.usesUrgentIngredient)
        XCTAssertTrue(suitability.urgentIngredients.isEmpty)
        XCTAssertEqual(suitability.expiredIngredients, ["Spinach"])

        let reasons = GenerateContextAwareRecommendationsUseCase.rankingReasons(
            for: suitability,
            context: .unrestricted
        )
        XCTAssertFalse(
            reasons.contains(.usesIngredientExpiringSoon),
            "Expired food must not earn an expiry ranking reason."
        )
    }

    func testNoExpiryDateIsHandledGracefully() {
        let recipe = Fixture.recipe(title: "Plain", ingredients: [
            Fixture.essential("Pasta", 100, .grams),
        ])
        let pantry = [Fixture.pantryItem("Pasta", 500, .grams, expiresInDays: nil)]

        guard let suitability = Fixture.suitability(of: recipe, pantry: pantry).suitable else {
            return XCTFail("Expected a suitable recipe.")
        }

        XCTAssertFalse(suitability.usesUrgentIngredient)
        XCTAssertFalse(suitability.usesExpiredIngredient)
        XCTAssertEqual(suitability.readiness, .readyToCook)
    }

    /// Four to seven days out is deliberately not urgent, matching
    /// `ExpiryState.shouldPrioritise` - so the Kitchen tab and the
    /// recommendation screen can never disagree about what is urgent.
    func testExpiryUrgencyMatchesExpiryService() {
        let recipe = Fixture.recipe(title: "Plain", ingredients: [
            Fixture.essential("Spinach", 100, .grams),
        ])

        for days in [0, 1, 2, 3] {
            let pantry = [Fixture.pantryItem("Spinach", 300, .grams, expiresInDays: days)]
            let suitability = Fixture.suitability(of: recipe, pantry: pantry).suitable
            XCTAssertEqual(
                suitability?.usesUrgentIngredient,
                true,
                "\(days) days out should be urgent."
            )
        }

        for days in [5, 20] {
            let pantry = [Fixture.pantryItem("Spinach", 300, .grams, expiresInDays: days)]
            let suitability = Fixture.suitability(of: recipe, pantry: pantry).suitable
            XCTAssertEqual(
                suitability?.usesUrgentIngredient,
                false,
                "\(days) days out should not be urgent."
            )
        }
    }

    func testMissingIngredientCannotBeCountedAsUrgent() {
        // The pantry holds Spinach, but the recipe needs Kale - no match,
        // so nothing is urgent even though an urgent item exists.
        let recipe = Fixture.recipe(title: "Kale Dish", ingredients: [
            Fixture.essential("Kale", 100, .grams),
        ])
        let pantry = [Fixture.pantryItem("Spinach", 300, .grams, expiresInDays: 1)]

        let suitability = Fixture.suitability(of: recipe, pantry: pantry).suitable
        XCTAssertEqual(suitability?.usesUrgentIngredient, false)
    }

    func testSameIngredientIsNotDoubleCounted() {
        // Two rows naming the same ingredient must credit the pantry item
        // once, not twice.
        let recipe = Fixture.recipe(title: "Double", ingredients: [
            Fixture.essential("Spinach", 50, .grams),
            Fixture.optional("spinach", 20, .grams),
        ])
        let pantry = [Fixture.pantryItem("Spinach", 300, .grams, expiresInDays: 1)]

        let suitability = Fixture.suitability(of: recipe, pantry: pantry).suitable
        XCTAssertEqual(suitability?.urgentIngredients.count, 1)
    }

    func testUrgentIngredientsAreOrderedMostUrgentFirst() {
        let recipe = Fixture.recipe(title: "Many", ingredients: [
            Fixture.essential("Spinach", 10, .grams),
            Fixture.essential("Cream", 10, .milliliters),
            Fixture.essential("Chicken", 10, .grams),
        ])
        let pantry = [
            Fixture.pantryItem("Spinach", 100, .grams, expiresInDays: 3),
            Fixture.pantryItem("Cream", 100, .milliliters, expiresInDays: 0),
            Fixture.pantryItem("Chicken", 100, .grams, expiresInDays: 1),
        ]

        let suitability = Fixture.suitability(of: recipe, pantry: pantry).suitable
        XCTAssertEqual(
            suitability?.urgentIngredients.map(\.ingredientName),
            ["Cream", "Chicken", "Spinach"]
        )
    }

    // MARK: - Kitchen inventory compatibility

    /// A packaged kitchen item carries `packageUnit`/`packageLevel` beside
    /// the canonical amount. Recommendations must read the canonical
    /// amount, exactly as recipe feasibility already does.
    func testPackagedKitchenItemIsReadThroughTheCanonicalAmount() {
        let recipe = Fixture.recipe(title: "Milk Dish", ingredients: [
            Fixture.essential("Milk", 1, .pieces),
        ])
        var item = PantryItem(
            ingredient: Ingredient(name: "Milk", category: .dairy),
            quantity: 1,
            unit: .pieces
        )
        // Half a bottle: 0.5 pcs canonically.
        item.setInventoryQuantity(.package(count: 1, unit: .bottle, level: .half))

        XCTAssertEqual(item.quantity, 0.5)
        let suitability = Fixture.suitability(of: recipe, pantry: [item]).suitable

        // 0.5 pcs does not cover 1 pcs, and the recommendation must say so
        // rather than matching on the name "Milk".
        XCTAssertEqual(suitability?.readiness, .needsOneToTwoIngredients)
        XCTAssertEqual(suitability?.shoppingIngredients, ["Milk"])
    }

    /// A legacy pantry item - no kitchen fields at all - must behave
    /// exactly as before.
    func testLegacyPantryItemWithoutKitchenFieldsWorks() {
        let recipe = Fixture.recipe(title: "Plain", ingredients: [
            Fixture.essential("Pasta", 100, .grams),
        ])
        let item = PantryItem(
            ingredient: Ingredient(name: "Pasta", category: .grain),
            quantity: 500,
            unit: .grams
        )

        XCTAssertNil(item.expiryDate)
        XCTAssertNil(item.storageLocation)
        XCTAssertNil(item.packageUnit)

        let suitability = Fixture.suitability(of: recipe, pantry: [item]).suitable
        XCTAssertEqual(suitability?.readiness, .readyToCook)
        XCTAssertFalse(suitability?.usesUrgentIngredient == true)
    }

    /// Storage location must not influence recommendations - food in the
    /// freezer is still food you have.
    func testStorageLocationDoesNotAffectSuitability() {
        let recipe = Fixture.recipe(title: "Plain", ingredients: [
            Fixture.essential("Peas", 100, .grams),
        ])
        let locations: [StorageLocation] = [.fridge, .freezer, .pantry]

        let readinesses = locations.map { location -> RecipeReadiness? in
            let item = PantryItem(
                ingredient: Ingredient(name: "Peas"),
                quantity: 500,
                unit: .grams,
                storageLocation: location
            )
            return Fixture.suitability(of: recipe, pantry: [item]).suitable?.readiness
        }

        XCTAssertEqual(readinesses, [.readyToCook, .readyToCook, .readyToCook])
    }

    // MARK: - Feasibility engine parity

    /// The extracted overload must agree with the fetching entry point.
    /// If these ever diverge there are two feasibility engines, which is
    /// precisely what this integration exists to avoid.
    func testExtractedFeasibilityOverloadMatchesFetchingEntryPoint() async throws {
        let recipe = Fixture.recipe(title: "Parity", ingredients: [
            Fixture.essential("Pasta", 200, .grams),
            Fixture.essential("Stock", 500, .milliliters),
            Fixture.optional("Basil", 5, .grams),
        ])
        let pantry = [
            Fixture.pantryItem("Pasta", 1, .kilograms),
            Fixture.pantryItem("Stock", 300, .grams),
        ]

        let viaRepository = try await EvaluateRecipeFeasibilityUseCase(
            pantryRepository: InMemoryPantryRepository(seedItems: pantry)
        ).execute(recipe: recipe)

        let direct = EvaluateRecipeFeasibilityUseCase.evaluate(recipe: recipe, against: pantry)

        XCTAssertEqual(viaRepository, direct)
    }
}
