//
//  SubstitutionCachePersistenceTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// Covers what the persistent layer adds on top of `SubstitutionCache`'s
/// in-process dictionary: a hit from a *different* cache instance, which is
/// what both "another screen" and "after a relaunch" look like from here.
@MainActor
final class SubstitutionCachePersistenceTests: XCTestCase {
    private func creamRecipe() -> Recipe {
        Recipe(
            title: "Creamy Pasta",
            summary: "Test fixture.",
            ingredients: [RecipeIngredient(ingredient: Ingredient(name: "Cream", category: .dairy), quantity: 200, unit: .milliliters, role: .essential)],
            instructions: ["Cook it."]
        )
    }

    private func feasibility(for recipe: Recipe) -> RecipeFeasibilityResult {
        RecipeFeasibilityResult(recipe: recipe, evaluatedIngredients: [], status: .notMakeable)
    }

    private func milkPantry() -> InMemoryPantryRepository {
        InMemoryPantryRepository(seedItems: [
            PantryItem(ingredient: Ingredient(name: "Milk", category: .dairy), quantity: 1000, unit: .milliliters),
        ])
    }

    private var milkSuggestion: RawSubstitutionSuggestion {
        RawSubstitutionSuggestion(ingredientName: "Milk", suggestedQuantity: nil, suggestedUnit: nil, confidence: nil, explanation: "Works.", limitations: nil)
    }

    private func suggestion(named name: String) -> SubstitutionSuggestion {
        SubstitutionSuggestion(
            ingredientName: name,
            suggestedQuantity: 200,
            suggestedUnit: .milliliters,
            confidence: 0.8,
            explanation: "Close enough in a sauce.",
            limitations: "Thinner result.",
            pantryQuantity: 1000,
            pantryUnit: .milliliters,
            validationStatus: .availableInPantry
        )
    }

    // MARK: - Sharing across instances

    /// The demo case: every screen builds its own `SubstitutionCache`, so a
    /// generation paid for on one must not be paid for again on the next.
    func test_execute_secondCacheInstanceSharingAStore_skipsProviderCall() async throws {
        let recipe = creamRecipe()
        let store = InMemorySubstitutionCacheStore()
        let pantry = milkPantry()
        let mockService = MockSubstitutionService(result: .success([milkSuggestion]))

        let first = GetIngredientSubstitutionsUseCase(
            substitutionService: mockService,
            pantryRepository: pantry,
            cache: SubstitutionCache(persistentStore: store)
        )
        let firstResult = try await first.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))

        let second = GetIngredientSubstitutionsUseCase(
            substitutionService: mockService,
            pantryRepository: pantry,
            cache: SubstitutionCache(persistentStore: store)
        )
        let secondResult = try await second.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))

        XCTAssertEqual(mockService.requestCount, 1)
        XCTAssertEqual(secondResult, firstResult)
    }

    /// Without a store the old behaviour stands: the cache is per instance,
    /// which is what previews and the rest of the test suite rely on.
    func test_execute_secondCacheInstanceWithoutAStore_callsProviderAgain() async throws {
        let recipe = creamRecipe()
        let pantry = milkPantry()
        let mockService = MockSubstitutionService(result: .success([milkSuggestion]))

        for _ in 0..<2 {
            let useCase = GetIngredientSubstitutionsUseCase(
                substitutionService: mockService,
                pantryRepository: pantry,
                cache: SubstitutionCache()
            )
            _ = try await useCase.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))
        }

        XCTAssertEqual(mockService.requestCount, 2)
    }

    /// A persisted entry must not outlive the pantry it was generated for.
    func test_execute_pantryChange_invalidatesPersistedEntry() async throws {
        let recipe = creamRecipe()
        let store = InMemorySubstitutionCacheStore()
        let pantry = milkPantry()
        let mockService = MockSubstitutionService(result: .success([milkSuggestion]))

        let first = GetIngredientSubstitutionsUseCase(
            substitutionService: mockService,
            pantryRepository: pantry,
            cache: SubstitutionCache(persistentStore: store)
        )
        _ = try await first.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))

        try await pantry.add(PantryItem(ingredient: Ingredient(name: "Butter", category: .dairy), quantity: 200, unit: .grams))

        let second = GetIngredientSubstitutionsUseCase(
            substitutionService: mockService,
            pantryRepository: pantry,
            cache: SubstitutionCache(persistentStore: store)
        )
        _ = try await second.execute(recipe: recipe, targetIngredient: recipe.ingredients[0], feasibility: feasibility(for: recipe))

        XCTAssertEqual(mockService.requestCount, 2)
    }

    /// "Nothing usable" is a filtered-out generation as often as a real
    /// answer, so it stays in memory and off disk.
    func test_store_emptyResult_isNotPersisted() {
        let store = InMemorySubstitutionCacheStore()
        let cache = SubstitutionCache(persistentStore: store)
        let key = SubstitutionCacheKey(recipeTitle: "Creamy Pasta", ingredientName: "Cream", pantryFingerprint: "abc")

        cache.store([], for: key)

        XCTAssertEqual(cache.suggestions(for: key), [])
        XCTAssertNil(store.loadSuggestions(forKey: key.persistentKey))
    }

    // MARK: - Key identity

    func test_cacheKey_normalisesCasingAndWhitespace() {
        let spelled = SubstitutionCacheKey(recipeTitle: "  Creamy Pasta ", ingredientName: "CREAM", pantryFingerprint: "abc")
        let plain = SubstitutionCacheKey(recipeTitle: "creamy pasta", ingredientName: "cream", pantryFingerprint: "abc")

        XCTAssertEqual(spelled, plain)
        XCTAssertEqual(spelled.persistentKey, plain.persistentKey)
    }

    /// The reason `Hasher` was dropped: a persisted key is only useful if the
    /// same pantry produces the same fingerprint, whatever order it arrives
    /// in - and, by extension, in a later launch.
    func test_pantryFingerprint_isOrderIndependentAndContentSensitive() {
        let milk = PantryItem(ingredient: Ingredient(name: "Milk", category: .dairy), quantity: 1000, unit: .milliliters)
        let butter = PantryItem(ingredient: Ingredient(name: "Butter", category: .dairy), quantity: 200, unit: .grams)

        XCTAssertEqual(
            SubstitutionCache.pantryFingerprint([milk, butter]),
            SubstitutionCache.pantryFingerprint([butter, milk])
        )
        XCTAssertNotEqual(
            SubstitutionCache.pantryFingerprint([milk, butter]),
            SubstitutionCache.pantryFingerprint([milk])
        )

        let lessMilk = PantryItem(ingredient: Ingredient(name: "Milk", category: .dairy), quantity: 500, unit: .milliliters)
        XCTAssertNotEqual(
            SubstitutionCache.pantryFingerprint([milk]),
            SubstitutionCache.pantryFingerprint([lessMilk])
        )
    }

    // MARK: - File-backed store

    func test_fileStore_roundTripsSuggestions() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("substitution-cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let written = [suggestion(named: "Milk")]
        SubstitutionCacheStore(fileURL: fileURL).save(written, forKey: "key")

        // A separate instance, as a relaunch would be.
        let reloaded = SubstitutionCacheStore(fileURL: fileURL).loadSuggestions(forKey: "key")

        XCTAssertEqual(reloaded, written)
    }

    func test_fileStore_missingFile_readsAsNoCache() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("substitution-cache-\(UUID().uuidString).json")

        XCTAssertNil(SubstitutionCacheStore(fileURL: fileURL).loadSuggestions(forKey: "key"))
    }

    func test_fileStore_corruptFile_readsAsNoCacheRatherThanThrowing() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("substitution-cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("not json".utf8).write(to: fileURL)

        let store = SubstitutionCacheStore(fileURL: fileURL)
        XCTAssertNil(store.loadSuggestions(forKey: "key"))

        // And a write over the top recovers rather than failing.
        store.save([suggestion(named: "Milk")], forKey: "key")
        XCTAssertEqual(store.loadSuggestions(forKey: "key")?.count, 1)
    }
}
