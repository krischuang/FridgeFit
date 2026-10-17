//
//  OnlineRecipeFeatureTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// The guarantees that let this feature ship with its API configuration
/// still outstanding: no key is needed, and nothing reaches the network.
@MainActor
final class OnlineRecipeFeatureTests: XCTestCase {

    // MARK: - Shipped state

    func test_shippedProviderState_isDisabled() {
        // The whole point of the gate. If this ever flips without the three
        // activation steps being done deliberately, this test is the alarm.
        XCTAssertEqual(OnlineRecipeFeature.provider, .disabled)
    }

    func test_shippedSavedRecipeStorageState_isDisabledPendingRulesDeployment() {
        XCTAssertEqual(OnlineRecipeFeature.savedRecipeStorage, .disabledPendingRulesDeployment)
    }

    // MARK: - No key required, and none read

    func test_disabledProvider_neverReadsAnAPIKey() {
        var loaderCallCount = 0
        _ = OnlineRecipeFeature.makeOnlineRecipeService(
            state: .disabled,
            configurationLoader: {
                loaderCallCount += 1
                return nil
            },
            cache: InMemoryOnlineRecipeCacheStore()
        )
        XCTAssertEqual(loaderCallCount, 0, "A disabled provider must short-circuit before any key is read")
    }

    func test_disabledProvider_buildsUnconfiguredService() {
        let service = OnlineRecipeFeature.makeOnlineRecipeService(
            state: .disabled,
            configurationLoader: { SpoonacularConfiguration(apiKey: "unused-in-this-test") },
            cache: InMemoryOnlineRecipeCacheStore()
        )
        XCTAssertTrue(
            service is UnconfiguredOnlineRecipeService,
            "No live service may be constructed while the provider is disabled, even with a key present"
        )
    }

    func test_enabledProviderWithoutKey_stillBuildsUnconfiguredService() {
        let service = OnlineRecipeFeature.makeOnlineRecipeService(
            state: .enabled,
            configurationLoader: { nil },
            cache: InMemoryOnlineRecipeCacheStore()
        )
        XCTAssertTrue(service is UnconfiguredOnlineRecipeService)
    }

    func test_enabledProviderWithKey_buildsCachingLiveService() {
        // Proves the activation path works, without calling it.
        let service = OnlineRecipeFeature.makeOnlineRecipeService(
            state: .enabled,
            configurationLoader: { SpoonacularConfiguration(apiKey: "test-key-not-a-credential") },
            cache: InMemoryOnlineRecipeCacheStore()
        )
        XCTAssertTrue(service is CachingOnlineRecipeService)
    }

    func test_noSpoonacularKeyIsConfiguredInThisBuild() {
        // The test host's Info.plist carries `$(SPOONACULAR_API_KEY)`, which
        // resolves to the unexpanded literal with no Secrets.xcconfig - and
        // `sanitized` rejects that. If a real key were ever committed, this
        // would start failing.
        XCTAssertNil(
            SpoonacularConfiguration.load(bundle: .main, environment: [:]),
            "A Spoonacular key is configured in this build; it must not be"
        )
    }

    // MARK: - No request while disabled

    func test_unconfiguredService_throwsNotConfigured_withoutNetworking() async {
        let service = UnconfiguredOnlineRecipeService()
        let criteria = OnlineRecipeSearchCriteria(
            pantryIngredientNames: ["rice"],
            preferences: .default
        )
        do {
            _ = try await service.searchRecipes(matching: criteria)
            XCTFail("Expected .notConfigured")
        } catch {
            XCTAssertEqual(error as? OnlineRecipeSearchError, .notConfigured)
        }
    }

    func test_searchThroughTheGatedStack_reportsNotConfigured() async {
        // End to end through the real use case and view model, using the
        // service the app actually builds today. The failure is an explained
        // configuration state, not a crash and not a network error.
        let viewModel = OnlineRecipeSearchViewModel(
            useCase: FindOnlineRecipesFromPantryUseCase(
                recipeService: OnlineRecipeFeature.makeOnlineRecipeService(
                    state: OnlineRecipeFeature.provider,
                    configurationLoader: { nil },
                    cache: InMemoryOnlineRecipeCacheStore()
                ),
                pantryRepository: OnlineRecipeFixtures.pantry("Rice")
            ),
            preferencesStore: InMemoryOnlineRecipePreferencesStore()
        )

        await viewModel.search()

        XCTAssertTrue(viewModel.matches.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, OnlineRecipeSearchError.notConfigured.errorDescription)
    }

    // MARK: - Saved recipe storage gate

    func test_disabledSavedRecipeStorage_buildsNoRepository() {
        var buildCallCount = 0
        let repository = OnlineRecipeFeature.makeSavedRecipeRepository(
            state: .disabledPendingRulesDeployment,
            build: {
                buildCallCount += 1
                return InMemorySavedRecipeRepository()
            }
        )
        XCTAssertNil(repository)
        XCTAssertEqual(buildCallCount, 0, "No Firestore repository may be constructed while rules are undeployed")
    }

    func test_enabledSavedRecipeStorage_buildsRepository() {
        let repository = OnlineRecipeFeature.makeSavedRecipeRepository(
            state: .enabled,
            build: { InMemorySavedRecipeRepository() }
        )
        XCTAssertNotNil(repository)
    }

    func test_saveActionIsNotOfferedWhileStorageIsGatedOff() async {
        // The requirement is specifically that no save action exists that
        // would fail with permission-denied against undeployed rules.
        let viewModel = RecipeViewModel(
            recipeRepository: InMemoryRecipeRepository(),
            pantryRepository: InMemoryPantryRepository(),
            savedRecipeRepository: OnlineRecipeFeature.makeSavedRecipeRepository(
                state: .disabledPendingRulesDeployment,
                build: { InMemorySavedRecipeRepository() }
            ),
            savedRecipeUnavailableExplanation: OnlineRecipeFeature.savedRecipeUnavailableExplanation(
                state: .disabledPendingRulesDeployment
            )
        )
        XCTAssertFalse(viewModel.canSaveRecipes)
        XCTAssertNotNil(
            viewModel.savedRecipeUnavailableExplanation,
            "Saving must be explained, not silently missing"
        )
    }

    func test_savingIsANoOpWhenNoRepositoryIsWired() async {
        let viewModel = RecipeViewModel(
            recipeRepository: InMemoryRecipeRepository(),
            pantryRepository: InMemoryPantryRepository()
        )
        await viewModel.saveOnlineRecipe(OnlineRecipeFixtures.recipe())

        XCTAssertTrue(viewModel.savedRecipes.isEmpty)
        XCTAssertNil(viewModel.savedRecipeErrorMessage, "A gated-off feature must not surface an error the user can't act on")
    }

    // MARK: - Explanations

    func test_disabledStates_haveUserFacingExplanations() {
        XCTAssertNotNil(OnlineRecipeFeature.providerUnavailableExplanation(state: .disabled))
        XCTAssertNotNil(OnlineRecipeFeature.savedRecipeUnavailableExplanation(state: .disabledPendingRulesDeployment))
    }

    func test_enabledStates_haveNoExplanationToShow() {
        XCTAssertNil(OnlineRecipeFeature.providerUnavailableExplanation(state: .enabled))
        XCTAssertNil(OnlineRecipeFeature.savedRecipeUnavailableExplanation(state: .enabled))
    }
}
