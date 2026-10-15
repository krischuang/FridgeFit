//
//  RecommendationSessionFeedbackTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// Covers the session-scoped feedback rules: what it hides, how it
/// reorders, that it is deterministic, and that it cannot touch stored
/// data.
final class RecommendationSessionFeedbackTests: XCTestCase {

    private typealias Fixture = RecommendationFixture

    // MARK: - Session value semantics

    func testRecordingReplacesAnEarlierActionForTheSameRecipe() {
        let recipeID = UUID()
        var session = RecommendationSession()

        session.record(SessionRecipeFeedback(recipeID: recipeID, action: .saved))
        XCTAssertEqual(session.feedback(for: recipeID), .saved)

        session.record(SessionRecipeFeedback(recipeID: recipeID, action: .skipped))
        XCTAssertEqual(session.feedback(for: recipeID), .skipped)
        XCTAssertEqual(session.recordedFeedback.count, 1)
    }

    func testClearingFeedbackRemovesIt() {
        let recipeID = UUID()
        var session = RecommendationSession()
        session.record(SessionRecipeFeedback(recipeID: recipeID, action: .saved))

        session.clearFeedback(for: recipeID)

        XCTAssertNil(session.feedback(for: recipeID))
        XCTAssertTrue(session.recordedFeedback.isEmpty)
    }

    func testEndedSessionHasNoInfluence() async throws {
        let skipped = Fixture.recipe(title: "Skipped")
        var session = RecommendationSession()
        session.record(SessionRecipeFeedback(recipeID: skipped.id, action: .skipped))
        session.end()

        let recommendations = try await Fixture.recommendations(
            recipes: [skipped, Fixture.recipe(title: "Other")],
            pantry: Fixture.stockedPantry,
            session: session
        )

        XCTAssertEqual(recommendations.count, 2, "An ended session must not hide anything.")
    }

    // MARK: - Skipping

    func testSkippedRecipeIsHidden() async throws {
        let skipped = Fixture.recipe(title: "Skipped")
        let kept = Fixture.recipe(title: "Kept")

        var session = RecommendationSession()
        session.record(SessionRecipeFeedback(recipeID: skipped.id, action: .skipped))

        let recommendations = try await Fixture.recommendations(
            recipes: [skipped, kept],
            pantry: Fixture.stockedPantry,
            session: session
        )

        XCTAssertEqual(recommendations.map(\.recipe.title), ["Kept"])
    }

    func testSkippingEverythingReportsEveryRecipeSkipped() async {
        let a = Fixture.recipe(title: "A")
        let b = Fixture.recipe(title: "B")

        var session = RecommendationSession()
        session.record(SessionRecipeFeedback(recipeID: a.id, action: .skipped))
        session.record(SessionRecipeFeedback(recipeID: b.id, action: .skipped))

        do {
            _ = try await Fixture.recommendations(
                recipes: [a, b],
                pantry: Fixture.stockedPantry,
                session: session
            )
            XCTFail("Expected a failure.")
        } catch let error as RecommendationGenerationError {
            XCTAssertEqual(error, .everyRecipeSkippedInSession)
        } catch {
            XCTFail("Unexpected error \(error).")
        }
    }

    // MARK: - Saving promotes similar recipes

    func testSavingARecipePromotesOthersSharingItsCuisine() async throws {
        let savedItalian = Fixture.recipe(title: "Saved Italian", cuisine: .italian, tastes: [.hearty])
        let otherItalian = Fixture.recipe(title: "Zzz Italian", cuisine: .italian, tastes: [.hearty])
        let asian = Fixture.recipe(title: "Aaa Asian", cuisine: .asian, tastes: [.fresh])

        // Without feedback, alphabetical ordering puts the Asian dish first.
        let baseline = try await Fixture.recommendations(
            recipes: [savedItalian, otherItalian, asian],
            pantry: Fixture.stockedPantry
        )
        XCTAssertEqual(baseline.first?.recipe.title, "Aaa Asian")

        var session = RecommendationSession()
        session.record(SessionRecipeFeedback(recipeID: savedItalian.id, action: .saved))

        let influenced = try await Fixture.recommendations(
            recipes: [savedItalian, otherItalian, asian],
            pantry: Fixture.stockedPantry,
            session: session
        )

        XCTAssertEqual(
            influenced.map(\.recipe.title),
            ["Saved Italian", "Zzz Italian", "Aaa Asian"],
            "Italian dishes should be promoted above the Asian one."
        )
    }

    // MARK: - Reporting deprioritises

    func testReportingNotMyTasteDeprioritisesThatCuisine() async throws {
        let reported = Fixture.recipe(title: "Aaa Reported", cuisine: .italian, tastes: [.hearty])
        let sameCuisine = Fixture.recipe(title: "Bbb Italian", cuisine: .italian, tastes: [.hearty])
        let different = Fixture.recipe(title: "Zzz Asian", cuisine: .asian, tastes: [.fresh])

        var session = RecommendationSession()
        session.record(
            SessionRecipeFeedback(recipeID: reported.id, action: .reported(.notMyTaste))
        )

        let recommendations = try await Fixture.recommendations(
            recipes: [reported, sameCuisine, different],
            pantry: Fixture.stockedPantry,
            session: session
        )

        XCTAssertEqual(
            recommendations.first?.recipe.title,
            "Zzz Asian",
            "The unaffected cuisine should rise despite sorting last alphabetically."
        )
        // Reported recipes are reordered, not hidden.
        XCTAssertEqual(recommendations.count, 3)
    }

    func testReportingTakesTooLongReordersByCookingTime() async throws {
        let reported = Fixture.recipe(title: "Aaa Long", minutes: 60)
        let quick = Fixture.recipe(title: "Zzz Quick", minutes: 10)
        let medium = Fixture.recipe(title: "Mmm Medium", minutes: 30)

        var session = RecommendationSession()
        session.record(
            SessionRecipeFeedback(recipeID: reported.id, action: .reported(.takesTooLong))
        )

        let recommendations = try await Fixture.recommendations(
            recipes: [reported, quick, medium],
            pantry: Fixture.stockedPantry,
            session: session
        )

        XCTAssertEqual(
            recommendations.map(\.recipe.title),
            ["Zzz Quick", "Mmm Medium", "Aaa Long"]
        )
    }

    func testReportingTooDifficultDeprioritisesThatDifficultyAndAbove() async throws {
        let reported = Fixture.recipe(title: "Aaa Moderate", difficulty: .moderate)
        let harder = Fixture.recipe(title: "Bbb Challenging", difficulty: .challenging)
        let easier = Fixture.recipe(title: "Zzz Easy", difficulty: .easy)

        var session = RecommendationSession()
        session.record(
            SessionRecipeFeedback(recipeID: reported.id, action: .reported(.tooDifficult))
        )

        let recommendations = try await Fixture.recommendations(
            recipes: [reported, harder, easier],
            pantry: Fixture.stockedPantry,
            session: session
        )

        XCTAssertEqual(
            recommendations.first?.recipe.title,
            "Zzz Easy",
            "Only the easy recipe is below the reported threshold."
        )
    }

    func testReportingTooMuchShoppingDeprioritisesRecipesNeedingAnything() async throws {
        let needsOne = Fixture.recipe(title: "Aaa Needs One", ingredients: [
            Fixture.essential("Pasta", 100, .grams),
            Fixture.essential("Capers", 10, .grams),
        ])
        let ready = Fixture.recipe(title: "Zzz Ready", ingredients: [
            Fixture.essential("Pasta", 100, .grams),
        ])

        var session = RecommendationSession()
        session.record(
            SessionRecipeFeedback(recipeID: needsOne.id, action: .reported(.tooMuchShopping))
        )

        let recommendations = try await Fixture.recommendations(
            recipes: [needsOne, ready],
            pantry: [Fixture.pantryItem("Pasta", 500, .grams)],
            session: session
        )

        XCTAssertEqual(recommendations.map(\.recipe.title), ["Zzz Ready", "Aaa Needs One"])
    }

    /// Negative feedback must beat positive similarity, or a user who has
    /// just rejected a cuisine keeps seeing it at the top.
    ///
    /// Note that `notMyTaste` deprioritises the reported recipe's cuisine
    /// *and* its tastes, so the fixtures below keep those vocabularies
    /// disjoint on purpose - a shared taste would deprioritise every
    /// recipe and the assertion would prove nothing. Titles are chosen so
    /// the alphabetical final tiebreak would produce a *different* order,
    /// which is what makes the feedback rank the thing being measured.
    func testNegativeFeedbackOutweighsSavedSimilarity() async throws {
        // Promotes italian + fresh.
        let saved = Fixture.recipe(title: "Zzz Saved", cuisine: .italian, tastes: [.fresh])
        // Deprioritises mexican + spicy.
        let reported = Fixture.recipe(title: "Mmm Reported", cuisine: .mexican, tastes: [.spicy])
        // Promoted by its fresh taste, deprioritised by its mexican
        // cuisine - the case under test.
        let conflicted = Fixture.recipe(title: "Aaa Conflicted", cuisine: .mexican, tastes: [.fresh])
        // Touched by neither.
        let neutral = Fixture.recipe(title: "Bbb Neutral", cuisine: .asian, tastes: [.mild])

        var session = RecommendationSession()
        session.record(SessionRecipeFeedback(recipeID: saved.id, action: .saved))
        session.record(
            SessionRecipeFeedback(recipeID: reported.id, action: .reported(.notMyTaste))
        )

        let recommendations = try await Fixture.recommendations(
            recipes: [saved, reported, conflicted, neutral],
            pantry: Fixture.stockedPantry,
            session: session
        )

        XCTAssertEqual(
            recommendations.map(\.recipe.title),
            ["Zzz Saved", "Bbb Neutral", "Aaa Conflicted", "Mmm Reported"],
            "Promoted, then untouched, then deprioritised - promotion must not rescue a deprioritised recipe."
        )
    }

    // MARK: - Determinism

    /// Two "too difficult" reports must produce the same threshold
    /// regardless of dictionary iteration order.
    func testInfluenceIsOrderIndependent() async throws {
        let moderate = Fixture.recipe(title: "Moderate", difficulty: .moderate)
        let challenging = Fixture.recipe(title: "Challenging", difficulty: .challenging)
        let easy = Fixture.recipe(title: "Easy", difficulty: .easy)
        let recipes = [moderate, challenging, easy]

        var session = RecommendationSession()
        session.record(
            SessionRecipeFeedback(recipeID: challenging.id, action: .reported(.tooDifficult))
        )
        session.record(
            SessionRecipeFeedback(recipeID: moderate.id, action: .reported(.tooDifficult))
        )

        var observed: Set<[String]> = []
        for _ in 0..<10 {
            let recommendations = try await Fixture.recommendations(
                recipes: recipes.shuffled(),
                pantry: Fixture.stockedPantry,
                session: session
            )
            observed.insert(recommendations.map(\.recipe.title))
        }

        XCTAssertEqual(observed.count, 1, "Ordering varied across runs: \(observed)")
        XCTAssertEqual(observed.first?.first, "Easy")
    }

    func testInfluenceIgnoresFeedbackForRecipesNoLongerInTheCatalogue() async throws {
        let present = Fixture.recipe(title: "Present")

        var session = RecommendationSession()
        // Feedback for a recipe id that isn't in the catalogue at all.
        session.record(SessionRecipeFeedback(recipeID: UUID(), action: .saved))
        session.record(
            SessionRecipeFeedback(recipeID: UUID(), action: .reported(.tooDifficult))
        )

        let recommendations = try await Fixture.recommendations(
            recipes: [present],
            pantry: Fixture.stockedPantry,
            session: session
        )

        XCTAssertEqual(recommendations.map(\.recipe.title), ["Present"])
    }

    // MARK: - Feedback cannot corrupt data

    /// Feedback holds recipe ids only. Recording it must leave both the
    /// catalogue and the pantry byte-identical.
    func testFeedbackDoesNotMutateRecipeOrPantryData() async throws {
        let recipes = [
            Fixture.recipe(title: "A"),
            Fixture.recipe(title: "B"),
        ]
        let pantry = Fixture.stockedPantry
        let pantryRepository = InMemoryPantryRepository(seedItems: pantry)
        let recipeRepository = InMemoryRecipeRepository(recipes: recipes)
        let useCase = GenerateContextAwareRecommendationsUseCase(
            recipeRepository: recipeRepository,
            pantryRepository: pantryRepository
        )

        var session = RecommendationSession()
        session.record(SessionRecipeFeedback(recipeID: recipes[0].id, action: .saved))
        session.record(
            SessionRecipeFeedback(recipeID: recipes[1].id, action: .reported(.notMyTaste))
        )

        _ = try? await useCase.execute(context: .unrestricted, session: session, now: Fixture.now)

        let recipesAfter = try await recipeRepository.fetchAll()
        let pantryAfter = try await pantryRepository.fetchAll()

        XCTAssertEqual(recipesAfter, recipes)
        XCTAssertEqual(pantryAfter, pantry)
    }

    func testSavedRecipeIDsReflectOnlySaves() {
        let saved = UUID()
        let skipped = UUID()
        var session = RecommendationSession()
        session.record(SessionRecipeFeedback(recipeID: saved, action: .saved))
        session.record(SessionRecipeFeedback(recipeID: skipped, action: .skipped))

        XCTAssertEqual(session.savedRecipeIDs, [saved])
    }
}
