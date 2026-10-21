//
//  RecommendationViewRenderingTests.swift
//  FridgeFitTests
//

import SwiftUI
import XCTest
@testable import FridgeFit

/// Forces the new SwiftUI views to evaluate their bodies against real
/// data, headlessly.
///
/// ## What this does and does not prove
///
/// `ImageRenderer` builds the view tree and rasterises it, so anything
/// that traps while a body is being evaluated - a bad index, a nil unwrap,
/// a layout that divides by zero - fails here. `FlowLayout` in particular
/// is custom layout code doing its own arithmetic, and this is what
/// exercises it.
///
/// It does **not** prove the interactive flow. Taps, swipe actions,
/// sheet presentation, navigation pushes and the resulting navigation bar
/// chrome are not exercised by rendering, and this project has no UI test
/// target to exercise them. Those remain for manual verification - see the
/// release report.
@MainActor
final class RecommendationViewRenderingTests: XCTestCase {

    private typealias Fixture = RecommendationFixture

    /// Renders `view` and asserts it produced a non-empty image.
    private func assertRenders(
        _ view: some View,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let renderer = ImageRenderer(content: view.frame(width: 390, height: 844))
        renderer.scale = 1
        guard let image = renderer.uiImage else {
            return XCTFail("View produced no image.", file: file, line: line)
        }
        XCTAssertGreaterThan(image.size.width, 0, file: file, line: line)
        XCTAssertGreaterThan(image.size.height, 0, file: file, line: line)
    }

    private func loadedViewModel(
        recipes: [Recipe],
        pantry: [PantryItem]
    ) async -> RecommendationViewModel {
        let viewModel = RecommendationViewModel(
            generateUseCase: Fixture.useCase(recipes: recipes, pantry: pantry)
        )
        await viewModel.generate()
        return viewModel
    }

    // MARK: - Rows

    /// The richest row the UI can produce: every reason chip, an urgent
    /// ingredient, an unverified amount and something still to buy, all at
    /// once. If `FlowLayout` mis-measures, it shows up here.
    func testRowRendersWithEveryExplanationPresent() async {
        let recipe = Fixture.recipe(
            title: "Everything",
            cuisine: .asian,
            tastes: [.spicy],
            dietaryLabels: [.vegan],
            minutes: 20,
            difficulty: .easy,
            ingredients: [
                Fixture.essential("Spinach", 50, .grams),
                Fixture.essential("Stock", 500, .milliliters),
                Fixture.essential("Capers", 10, .grams),
            ]
        )
        // Relative to the real clock: these go through the view model,
        // which measures expiry from `Date.now`.
        let pantry = [
            Fixture.pantryItemExpiringFromToday("Spinach", 300, .grams, inDays: 1),
            Fixture.pantryItem("Stock", 900, .grams),
        ]

        let viewModel = RecommendationViewModel(
            generateUseCase: Fixture.useCase(recipes: [recipe], pantry: pantry)
        )
        viewModel.draftContext = CookingContext(
            maximumCookingTime: .thirtyMinutes,
            maximumDifficulty: .moderate,
            preferredCuisines: [.asian],
            preferredTastes: [.spicy],
            dietaryRestrictions: [.vegan]
        )
        await viewModel.generate()

        guard let recommendation = viewModel.recommendations.first else {
            return XCTFail("Expected a recommendation to render.")
        }
        // Precondition: this really is the rich case.
        XCTAssertTrue(recommendation.suitability.usesUrgentIngredient)
        XCTAssertFalse(recommendation.suitability.unverifiedIngredients.isEmpty)
        XCTAssertFalse(recommendation.suitability.shoppingIngredients.isEmpty)
        XCTAssertGreaterThanOrEqual(recommendation.rankingReasons.count, 4)

        assertRenders(
            List { RecommendationRow(recommendation: recommendation, feedback: .saved) }
        )
    }

    func testRowRendersForAnExpiredIngredientCaution() async {
        let recipe = Fixture.recipe(title: "Risky", ingredients: [
            Fixture.essential("Spinach", 50, .grams),
        ])
        let pantry = [Fixture.pantryItemExpiringFromToday("Spinach", 300, .grams, inDays: -3)]
        let viewModel = await loadedViewModel(recipes: [recipe], pantry: pantry)

        guard let recommendation = viewModel.recommendations.first else {
            return XCTFail("Expected a recommendation to render.")
        }
        XCTAssertTrue(recommendation.suitability.usesExpiredIngredient)

        assertRenders(
            List { RecommendationRow(recommendation: recommendation, feedback: nil) }
        )
    }

    /// A legacy recipe states no metadata, so the row has no metadata line
    /// and almost no chips - the opposite extreme from the rich case.
    func testRowRendersForALegacyRecipeWithNoMetadata() async {
        let viewModel = await loadedViewModel(
            recipes: [Fixture.legacyRecipe(title: "Legacy")],
            pantry: Fixture.stockedPantry
        )

        guard let recommendation = viewModel.recommendations.first else {
            return XCTFail("Expected a recommendation to render.")
        }
        assertRenders(
            List { RecommendationRow(recommendation: recommendation, feedback: nil) }
        )
    }

    func testEveryFeedbackBadgeRenders() {
        let actions: [SessionRecipeFeedbackAction] = [
            .saved,
            .skipped,
        ] + SessionRecipeFeedbackReason.allCases.map { .reported($0) }

        for action in actions {
            assertRenders(FeedbackBadge(action: action))
        }
    }

    func testEveryReasonChipRenders() {
        for reason in RecommendationReason.allCases {
            assertRenders(RecommendationReasonChip(reason: reason))
        }
    }

    /// `FlowLayout` has to wrap when the chips exceed one line. Rendering
    /// at a deliberately narrow width forces that path.
    func testReasonChipsWrapAtANarrowWidth() {
        let chips = FlowLayout(spacing: 6) {
            ForEach(RecommendationReason.allCases, id: \.self) { reason in
                RecommendationReasonChip(reason: reason)
            }
        }
        let renderer = ImageRenderer(content: chips.frame(width: 180))
        renderer.scale = 1
        XCTAssertNotNil(renderer.uiImage, "Chips failed to lay out at a narrow width.")
    }

    // MARK: - Screens

    func testRecommendationsScreenRendersWithResults() async {
        let pantry = InMemoryPantryRepository(seedItems: [
            Fixture.pantryItem("Rice", 600, .grams),
            Fixture.pantryItem("Black Beans", 500, .grams),
            Fixture.pantryItemExpiringFromToday("Onion", 3, .pieces, inDays: 1),
            Fixture.pantryItem("Garlic", 4, .pieces),
        ])
        let recipes = BundledRecipeRepository()
        let viewModel = RecommendationViewModel(
            generateUseCase: GenerateContextAwareRecommendationsUseCase(
                recipeRepository: recipes,
                pantryRepository: pantry
            )
        )
        await viewModel.generate()
        XCTAssertTrue(viewModel.hasRecommendations)

        assertRenders(
            NavigationStack {
                RecipeRecommendationsView(
                    viewModel: viewModel,
                    recipeViewModel: RecipeViewModel(recipeRepository: recipes, pantryRepository: pantry),
                    substitutionViewModel: Self.substitutionViewModel(pantry: pantry)
                )
            }
        )
    }

    /// Each failure state has its own `ContentUnavailableView` and its own
    /// recovery button, so each is rendered.
    func testRecommendationsScreenRendersEveryFailureState() async {
        let cases: [(String, RecommendationViewModel)] = [
            ("empty pantry", RecommendationViewModel(
                generateUseCase: Fixture.useCase(recipes: [Fixture.recipe(title: "A")], pantry: [])
            )),
            ("unreadable pantry", RecommendationViewModel(
                generateUseCase: GenerateContextAwareRecommendationsUseCase(
                    recipeRepository: InMemoryRecipeRepository(recipes: [Fixture.recipe(title: "A")]),
                    pantryRepository: UnavailablePantryRepository()
                )
            )),
            ("empty catalogue", RecommendationViewModel(
                generateUseCase: Fixture.useCase(recipes: [], pantry: Fixture.stockedPantry)
            )),
        ]

        let pantry = InMemoryPantryRepository()
        for (name, viewModel) in cases {
            await viewModel.generate()
            XCTAssertNotNil(viewModel.failure, "\(name) should have failed.")
            assertRenders(
                NavigationStack {
                    RecipeRecommendationsView(
                        viewModel: viewModel,
                        recipeViewModel: RecipeViewModel(recipeRepository: InMemoryRecipeRepository(), pantryRepository: pantry),
                        substitutionViewModel: Self.substitutionViewModel(pantry: pantry)
                    )
                }
            )
        }
    }

    /// The filter-exclusion state is the one with an "Adjust Preferences"
    /// button rather than "Try Again".
    func testRecommendationsScreenRendersTheAdjustPreferencesState() async {
        let viewModel = RecommendationViewModel(
            generateUseCase: Fixture.useCase(
                recipes: [Fixture.recipe(title: "Slow", minutes: 60)],
                pantry: Fixture.stockedPantry
            )
        )
        viewModel.draftContext = CookingContext(maximumCookingTime: .fifteenMinutes)
        await viewModel.generate()
        XCTAssertEqual(viewModel.failure, .filtersExcludeFeasibleRecipes)
        XCTAssertTrue(viewModel.failure?.isResolvedByAdjustingPreferences == true)

        let pantry = InMemoryPantryRepository()
        assertRenders(
            NavigationStack {
                RecipeRecommendationsView(
                    viewModel: viewModel,
                    recipeViewModel: RecipeViewModel(recipeRepository: InMemoryRecipeRepository(), pantryRepository: pantry),
                    substitutionViewModel: Self.substitutionViewModel(pantry: pantry)
                )
            }
        )
    }

    func testPreferenceFormRenders() {
        assertRenders(CookingContextFormView(context: .unrestricted) { _ in })
    }

    /// The form must show every restriction it offers *and* every one it
    /// refuses, so both sections are populated before rendering.
    func testPreferenceFormRendersBothDietarySections() {
        XCTAssertFalse(DietaryRestriction.assessableCases.isEmpty)
        XCTAssertFalse(DietaryRestriction.unassessableCases.isEmpty)

        let context = CookingContext(
            maximumCookingTime: .fifteenMinutes,
            maximumDifficulty: .easy,
            preferredCuisines: Set(Cuisine.allCases),
            preferredTastes: Set(TastePreference.allCases),
            dietaryRestrictions: Set(DietaryRestriction.assessableCases)
        )
        assertRenders(CookingContextFormView(context: context) { _ in })
    }

    /// The Recipes tab starts with recommendations and pushes the original
    /// catalogue from the same navigation stack.
    func testRecipesTabRendersWithTheCatalogueEntryPoint() async {
        let pantry = InMemoryPantryRepository(seedItems: Fixture.stockedPantry)
        let recipes = BundledRecipeRepository()
        let recipeViewModel = RecipeViewModel(recipeRepository: recipes, pantryRepository: pantry)
        let recommendationViewModel = RecommendationViewModel(
            generateUseCase: GenerateContextAwareRecommendationsUseCase(
                recipeRepository: recipes,
                pantryRepository: pantry
            )
        )
        await recommendationViewModel.generate()

        assertRenders(
            NavigationStack {
                RecipeRecommendationsView(
                    viewModel: recommendationViewModel,
                    recipeViewModel: recipeViewModel,
                    substitutionViewModel: Self.substitutionViewModel(pantry: pantry),
                    suggestionViewModel: RecipeSuggestionViewModel(
                        useCase: SuggestRecipesFromPantryUseCase(
                            suggestionService: MockRecipeSuggestionService(),
                            pantryRepository: pantry
                        )
                    )
                )
            }
        )
    }

    private static func substitutionViewModel(pantry: PantryRepository) -> SubstitutionViewModel {
        SubstitutionViewModel(
            useCase: GetIngredientSubstitutionsUseCase(
                substitutionService: MockSubstitutionService(),
                pantryRepository: pantry,
                cache: SubstitutionCache()
            )
        )
    }
}
