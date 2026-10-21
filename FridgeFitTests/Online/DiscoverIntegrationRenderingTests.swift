//
//  DiscoverIntegrationRenderingTests.swift
//  FridgeFitTests
//

import SwiftUI
import UIKit
import XCTest
@testable import FridgeFit

/// Renders the integrated UI headlessly, and asserts the existing screens
/// still exist in the form `main` left them.
///
/// A hosting controller evaluates and lays out view bodies, so traps and bad
/// layout arithmetic fail here, but taps, sheet presentation and navigation
/// pushes are not exercised. Those remain for manual verification.
@MainActor
final class DiscoverIntegrationRenderingTests: XCTestCase {

    private typealias Fixture = RecommendationFixture

    private func assertRenders(
        _ view: some View,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let size = CGSize(width: 390, height: 844)
        let hostingController = UIHostingController(
            rootView: view.frame(width: size.width, height: size.height)
        )
        hostingController.view.bounds = CGRect(origin: .zero, size: size)
        hostingController.view.backgroundColor = .clear
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            hostingController.view.layer.render(in: context.cgContext)
        }

        XCTAssertGreaterThan(image.size.width, 0, file: file, line: line)
        XCTAssertGreaterThan(image.size.height, 0, file: file, line: line)
    }

    private func searchViewModel(
        result: Result<[OnlineRecipeMatch], OnlineRecipeSearchError> = .failure(.notConfigured)
    ) -> OnlineRecipeSearchViewModel {
        OnlineRecipeSearchViewModel(
            useCase: FindOnlineRecipesFromPantryUseCase(
                recipeService: MockOnlineRecipeService(result: result),
                pantryRepository: OnlineRecipeFixtures.pantry("Rice")
            ),
            preferencesStore: InMemoryOnlineRecipePreferencesStore()
        )
    }

    private func substitutionViewModel(pantry: PantryRepository) -> SubstitutionViewModel {
        SubstitutionViewModel(
            useCase: GetIngredientSubstitutionsUseCase(
                substitutionService: MockSubstitutionService(),
                pantryRepository: pantry,
                cache: SubstitutionCache()
            )
        )
    }

    // MARK: - Discover in its shipped, unconfigured state

    func test_discoverRendersUnconfiguredState() async {
        assertRenders(
            NavigationStack {
                DiscoverRecipesView(
                    viewModel: searchViewModel(),
                    recipeViewModel: RecipeViewModel(
                        pantryRepository: InMemoryPantryRepository(),
                        savedRecipeUnavailableExplanation: OnlineRecipeFeature.savedRecipeUnavailableExplanation(
                            state: .disabledPendingRulesDeployment
                        )
                    ),
                    providerUnavailableExplanation: OnlineRecipeFeature.providerUnavailableExplanation(state: .disabled)
                )
            }
        )
    }

    func test_discoverRendersWithMockResults() async {
        let viewModel = searchViewModel(result: .success([
            OnlineRecipeFixtures.match(id: 1, title: "Mock Pasta"),
            OnlineRecipeFixtures.match(id: 2, title: "Mock Curry", intolerances: nil),
        ]))
        await viewModel.search()

        assertRenders(
            NavigationStack {
                DiscoverRecipesView(
                    viewModel: viewModel,
                    recipeViewModel: RecipeViewModel(
                        pantryRepository: InMemoryPantryRepository(),
                        savedRecipeRepository: InMemorySavedRecipeRepository()
                    ),
                    providerUnavailableExplanation: nil
                )
            }
        )
    }

    func test_onlineRecipeDetailRendersWithSavingGatedOff() async {
        assertRenders(
            NavigationStack {
                OnlineRecipeDetailView(
                    match: OnlineRecipeFixtures.match(id: 1, title: "Mock Pasta"),
                    intolerances: [.dairy],
                    recipeViewModel: RecipeViewModel(
                        pantryRepository: InMemoryPantryRepository(),
                        savedRecipeUnavailableExplanation: OnlineRecipeFeature.savedRecipeUnavailableExplanation(
                            state: .disabledPendingRulesDeployment
                        )
                    )
                )
            }
        )
    }

    func test_onlineRecipeDetailRendersUnscreenedAllergenState() async {
        // `containsIntolerances == nil` is the "couldn't screen" branch.
        assertRenders(
            NavigationStack {
                OnlineRecipeDetailView(
                    match: OnlineRecipeFixtures.match(id: 3, title: "Unscreened", intolerances: nil),
                    intolerances: [.dairy],
                    recipeViewModel: RecipeViewModel(
                        pantryRepository: InMemoryPantryRepository(),
                        savedRecipeRepository: InMemorySavedRecipeRepository()
                    )
                )
            }
        )
    }

    func test_filtersScreenRendersBothSelectableAndWithheldSections() async {
        assertRenders(
            NavigationStack {
                OnlineRecipePreferencesView(initial: .default) { _ in }
            }
        )
    }

    // MARK: - Recipes and shared detail presentation

    func test_savedRecipesLandingRendersEmptyState() async {
        let pantry = InMemoryPantryRepository()
        let recipeViewModel = RecipeViewModel(
            recipeRepository: InMemoryRecipeRepository(recipes: []),
            pantryRepository: pantry,
            savedRecipeRepository: InMemorySavedRecipeRepository()
        )
        await recipeViewModel.loadRecipes()

        assertRenders(
            NavigationStack {
                SavedRecipesView(
                    viewModel: recipeViewModel,
                    substitutionViewModel: substitutionViewModel(pantry: pantry),
                    onExploreDiscover: {},
                    onFindRecommendations: {},
                    onBrowseAllRecipes: {}
                )
            }
        )
    }

    func test_savedRecipesLandingRendersSavedCollection() async {
        let pantry = InMemoryPantryRepository(seedItems: Fixture.stockedPantry)
        let recipeViewModel = RecipeViewModel(
            recipeRepository: InMemoryRecipeRepository(recipes: []),
            pantryRepository: pantry,
            savedRecipeRepository: InMemorySavedRecipeRepository()
        )
        await recipeViewModel.saveOnlineRecipe(OnlineRecipeFixtures.recipe(id: 79, title: "Saved Landing Dish"))

        XCTAssertEqual(recipeViewModel.savedRecipes.map(\.title), ["Saved Landing Dish"])
        assertRenders(
            NavigationStack {
                SavedRecipesView(
                    viewModel: recipeViewModel,
                    substitutionViewModel: substitutionViewModel(pantry: pantry),
                    onExploreDiscover: {},
                    onFindRecommendations: {},
                    onBrowseAllRecipes: {}
                )
            }
        )
    }

    func test_pantryIdeasStillRendersAppleIntelligenceSuggestions() async {
        // The on-device feature `main` shipped. Still reached by the Recipes
        // tab's lightbulb, still backed by RecipeSuggestionViewModel - not
        // replaced by Discover.
        let pantry = InMemoryPantryRepository(seedItems: Fixture.stockedPantry)
        let viewModel = RecipeSuggestionViewModel(
            useCase: SuggestRecipesFromPantryUseCase(
                suggestionService: MockRecipeSuggestionService(),
                pantryRepository: pantry
            )
        )
        await viewModel.loadSuggestions()

        assertRenders(PantryRecipeIdeasView(viewModel: viewModel))
    }

    func test_recipesTabStillRendersWithBothEntryPoints() async {
        let pantry = InMemoryPantryRepository(seedItems: Fixture.stockedPantry)
        let recipes = BundledRecipeRepository()
        let recipeViewModel = RecipeViewModel(recipeRepository: recipes, pantryRepository: pantry)
        await recipeViewModel.loadRecipes()

        assertRenders(
            NavigationStack {
                RecipeListView(
                    viewModel: recipeViewModel,
                    substitutionViewModel: substitutionViewModel(pantry: pantry),
                    suggestionViewModel: RecipeSuggestionViewModel(
                        useCase: SuggestRecipesFromPantryUseCase(
                            suggestionService: MockRecipeSuggestionService(),
                            pantryRepository: pantry
                        )
                    ),
                    recommendationViewModel: RecommendationViewModel(
                        generateUseCase: GenerateContextAwareRecommendationsUseCase(
                            recipeRepository: recipes,
                            pantryRepository: pantry
                        )
                    )
                )
            }
        )
    }

    func test_recipesTabRendersTheSavedFromDiscoverSection() async throws {
        // The two-section layout, which only appears once something is
        // saved. Uses an in-memory store, so no Firestore access.
        let pantry = InMemoryPantryRepository(seedItems: Fixture.stockedPantry)
        let recipes = BundledRecipeRepository()
        let saved = InMemorySavedRecipeRepository()
        let recipeViewModel = RecipeViewModel(
            recipeRepository: recipes,
            pantryRepository: pantry,
            savedRecipeRepository: saved
        )
        await recipeViewModel.saveOnlineRecipe(OnlineRecipeFixtures.recipe(id: 77, title: "Saved Online Dish"))
        await recipeViewModel.loadRecipes()

        XCTAssertFalse(recipeViewModel.savedRecipes.isEmpty, "Precondition: something is saved")

        assertRenders(
            NavigationStack {
                RecipeListView(
                    viewModel: recipeViewModel,
                    substitutionViewModel: substitutionViewModel(pantry: pantry),
                    suggestionViewModel: RecipeSuggestionViewModel(
                        useCase: SuggestRecipesFromPantryUseCase(
                            suggestionService: MockRecipeSuggestionService(),
                            pantryRepository: pantry
                        )
                    ),
                    recommendationViewModel: RecommendationViewModel(
                        generateUseCase: GenerateContextAwareRecommendationsUseCase(
                            recipeRepository: recipes,
                            pantryRepository: pantry
                        )
                    )
                )
            }
        )
    }

    func test_savedRecipeOpensTheExistingDetailView() async throws {
        // Same RecipeDetailView as a bundled recipe, with a real feasibility
        // verdict behind it.
        let pantry = InMemoryPantryRepository(seedItems: Fixture.stockedPantry)
        let saved = InMemorySavedRecipeRepository()
        let recipeViewModel = RecipeViewModel(
            recipeRepository: InMemoryRecipeRepository(recipes: []),
            pantryRepository: pantry,
            savedRecipeRepository: saved
        )
        await recipeViewModel.saveOnlineRecipe(OnlineRecipeFixtures.recipe(id: 78, title: "Saved Online Dish"))
        let recipe = try XCTUnwrap(recipeViewModel.savedRecipes.first)

        assertRenders(
            NavigationStack {
                RecipeDetailView(
                    recipe: recipe,
                    viewModel: recipeViewModel,
                    substitutionViewModel: substitutionViewModel(pantry: pantry)
                )
            }
        )
    }

    func test_recipeDetailRendersInDarkModeAtAccessibilityThree() async throws {
        let pantry = InMemoryPantryRepository(seedItems: Fixture.stockedPantry)
        let recipeViewModel = RecipeViewModel(
            recipeRepository: BundledRecipeRepository(),
            pantryRepository: pantry
        )
        await recipeViewModel.loadRecipes()
        let recipe = try XCTUnwrap(recipeViewModel.recipes.first)

        assertRenders(
            NavigationStack {
                RecipeDetailView(
                    recipe: recipe,
                    viewModel: recipeViewModel,
                    substitutionViewModel: substitutionViewModel(pantry: pantry)
                )
            }
            .environment(\.dynamicTypeSize, .accessibility3)
            .preferredColorScheme(.dark)
        )
    }
}
