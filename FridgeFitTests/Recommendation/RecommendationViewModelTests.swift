//
//  RecommendationViewModelTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// Covers the view model's state transitions and that it drives the real
/// use case over main's repository abstractions.
@MainActor
final class RecommendationViewModelTests: XCTestCase {

    private typealias Fixture = RecommendationFixture

    private func viewModel(
        recipes: [Recipe],
        pantry: [PantryItem]
    ) -> RecommendationViewModel {
        RecommendationViewModel(
            generateUseCase: Fixture.useCase(recipes: recipes, pantry: pantry)
        )
    }

    // MARK: - Generating

    /// `async` even though nothing is awaited: a synchronous test method
    /// on a `@MainActor` class aborts under this project's
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting, which is why
    /// every test in main's other `@MainActor` suites is async too.
    func testInitialStateIsEmptyAndHasNotRun() async {
        let sut = viewModel(recipes: [Fixture.recipe(title: "A")], pantry: Fixture.stockedPantry)

        XCTAssertFalse(sut.hasRun)
        XCTAssertFalse(sut.hasRecommendations)
        XCTAssertNil(sut.failure)
        XCTAssertNil(sut.appliedContext)
        XCTAssertEqual(sut.draftContext, .unrestricted)
    }

    func testGeneratePublishesRankedRecommendations() async {
        let sut = viewModel(
            recipes: [
                Fixture.recipe(title: "Needs One", ingredients: [
                    Fixture.essential("Pasta", 100, .grams),
                    Fixture.essential("Capers", 10, .grams),
                ]),
                Fixture.recipe(title: "Ready", ingredients: [
                    Fixture.essential("Pasta", 100, .grams),
                ]),
            ],
            pantry: [Fixture.pantryItem("Pasta", 500, .grams)]
        )

        await sut.generate()

        XCTAssertTrue(sut.hasRun)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.failure)
        XCTAssertEqual(sut.recommendations.map(\.recipe.title), ["Ready", "Needs One"])
        XCTAssertEqual(sut.appliedContext, .unrestricted)
    }

    func testEmptyPantryPublishesDomainFailureNotAString() async {
        let sut = viewModel(recipes: [Fixture.recipe(title: "A")], pantry: [])

        await sut.generate()

        XCTAssertEqual(sut.failure, .pantryNeedsIngredients)
        XCTAssertNil(sut.unexpectedErrorMessage)
        XCTAssertFalse(sut.hasRecommendations)
    }

    func testFilterFailureIsFlaggedAsResolvableByPreferences() async {
        let sut = viewModel(
            recipes: [Fixture.recipe(title: "Slow", minutes: 60)],
            pantry: Fixture.stockedPantry
        )
        sut.draftContext = CookingContext(maximumCookingTime: .fifteenMinutes)

        await sut.generate()

        XCTAssertEqual(sut.failure, .filtersExcludeFeasibleRecipes)
        XCTAssertTrue(sut.failure?.isResolvedByAdjustingPreferences == true)
    }

    func testApplyingPreferencesChangesResults() async {
        let sut = viewModel(
            recipes: [
                Fixture.recipe(title: "Quick", minutes: 10),
                Fixture.recipe(title: "Slow", minutes: 60),
            ],
            pantry: Fixture.stockedPantry
        )

        await sut.generate()
        XCTAssertEqual(sut.recommendations.count, 2)

        sut.draftContext = CookingContext(maximumCookingTime: .fifteenMinutes)
        await sut.generate()

        XCTAssertEqual(sut.recommendations.map(\.recipe.title), ["Quick"])
        XCTAssertEqual(sut.appliedContext?.maximumCookingTime, .fifteenMinutes)
    }

    func testFailureIsClearedByASubsequentSuccessfulRun() async {
        let sut = viewModel(
            recipes: [Fixture.recipe(title: "Slow", minutes: 60)],
            pantry: Fixture.stockedPantry
        )
        sut.draftContext = CookingContext(maximumCookingTime: .fifteenMinutes)
        await sut.generate()
        XCTAssertNotNil(sut.failure)

        sut.draftContext = .unrestricted
        await sut.generate()

        XCTAssertNil(sut.failure)
        XCTAssertTrue(sut.hasRecommendations)
    }

    // MARK: - Session feedback

    func testSkippingRemovesTheRecipeAndReRanks() async {
        let skipped = Fixture.recipe(title: "Skip Me")
        let kept = Fixture.recipe(title: "Keep Me")
        let sut = viewModel(recipes: [skipped, kept], pantry: Fixture.stockedPantry)

        await sut.generate()
        XCTAssertEqual(sut.recommendations.count, 2)

        await sut.record(.skipped, for: skipped)

        XCTAssertEqual(sut.recommendations.map(\.recipe.title), ["Keep Me"])
        XCTAssertEqual(sut.feedback(for: skipped), .skipped)
    }

    func testSavingIsRecordedAndCounted() async {
        let saved = Fixture.recipe(title: "Save Me")
        let sut = viewModel(recipes: [saved, Fixture.recipe(title: "Other")], pantry: Fixture.stockedPantry)

        await sut.generate()
        await sut.record(.saved, for: saved)

        XCTAssertEqual(sut.feedback(for: saved), .saved)
        XCTAssertEqual(sut.savedRecipeCount, 1)
        // A save never hides anything.
        XCTAssertEqual(sut.recommendations.count, 2)
    }

    func testReportingKeepsTheRecipeVisible() async {
        let reported = Fixture.recipe(title: "Reported")
        let sut = viewModel(recipes: [reported, Fixture.recipe(title: "Other")], pantry: Fixture.stockedPantry)

        await sut.generate()
        await sut.record(.reported(.notMyTaste), for: reported)

        XCTAssertEqual(sut.feedback(for: reported), .reported(.notMyTaste))
        XCTAssertEqual(sut.recommendations.count, 2)
    }

    func testClearingFeedbackRestoresASkippedRecipe() async {
        let skipped = Fixture.recipe(title: "Skip Me")
        let sut = viewModel(recipes: [skipped, Fixture.recipe(title: "Other")], pantry: Fixture.stockedPantry)

        await sut.generate()
        await sut.record(.skipped, for: skipped)
        XCTAssertEqual(sut.recommendations.count, 1)

        await sut.clearFeedback(for: skipped)

        XCTAssertEqual(sut.recommendations.count, 2)
        XCTAssertNil(sut.feedback(for: skipped))
    }

    func testStartingANewSessionBringsSkippedRecipesBack() async {
        let skipped = Fixture.recipe(title: "Skip Me")
        let sut = viewModel(recipes: [skipped, Fixture.recipe(title: "Other")], pantry: Fixture.stockedPantry)

        await sut.generate()
        await sut.record(.skipped, for: skipped)
        XCTAssertEqual(sut.recommendations.count, 1)

        await sut.startNewSession()

        XCTAssertEqual(sut.recommendations.count, 2)
        XCTAssertTrue(sut.session.recordedFeedback.isEmpty)
        XCTAssertEqual(sut.savedRecipeCount, 0)
    }

    func testRegenerateReusesTheAppliedContextNotTheDraft() async {
        let sut = viewModel(
            recipes: [
                Fixture.recipe(title: "Quick", minutes: 10),
                Fixture.recipe(title: "Slow", minutes: 60),
            ],
            pantry: Fixture.stockedPantry
        )
        sut.draftContext = CookingContext(maximumCookingTime: .fifteenMinutes)
        await sut.generate()
        XCTAssertEqual(sut.recommendations.count, 1)

        // A draft edit that was never applied must not leak into a refresh.
        sut.draftContext = .unrestricted
        await sut.regenerate()

        XCTAssertEqual(sut.recommendations.map(\.recipe.title), ["Quick"])
    }

    // MARK: - Fresh pantry reads

    /// Recommendations must reflect pantry changes made elsewhere in the
    /// app without any sync step, the same way `RecipeViewModel` does.
    func testRegeneratingPicksUpPantryChanges() async {
        let recipe = Fixture.recipe(title: "Needs Capers", ingredients: [
            Fixture.essential("Pasta", 100, .grams),
            Fixture.essential("Capers", 10, .grams),
        ])
        let pantryRepository = InMemoryPantryRepository(seedItems: [
            Fixture.pantryItem("Pasta", 500, .grams),
        ])
        let sut = RecommendationViewModel(
            generateUseCase: GenerateContextAwareRecommendationsUseCase(
                recipeRepository: InMemoryRecipeRepository(recipes: [recipe]),
                pantryRepository: pantryRepository
            )
        )

        await sut.generate()
        XCTAssertEqual(sut.recommendations.first?.readiness, .needsOneToTwoIngredients)

        // Something is added in Pantry or Kitchen.
        try? await pantryRepository.add(Fixture.pantryItem("Capers", 50, .grams))
        await sut.regenerate()

        XCTAssertEqual(sut.recommendations.first?.readiness, .readyToCook)
    }

    func testUnexpectedRepositoryFailureIsSurfacedAsADomainFailure() async {
        let sut = RecommendationViewModel(
            generateUseCase: GenerateContextAwareRecommendationsUseCase(
                recipeRepository: InMemoryRecipeRepository(recipes: [Fixture.recipe(title: "A")]),
                pantryRepository: UnavailablePantryRepository()
            )
        )

        await sut.generate()

        XCTAssertEqual(sut.failure, .pantryInformationUnavailable)
        XCTAssertFalse(sut.isLoading)
    }
}
