//
//  CompositeRecipeRepositoryTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class CompositeRecipeRepositoryTests: XCTestCase {

    private func recipe(_ title: String, id: UUID = UUID()) -> Recipe {
        Recipe(
            id: id,
            title: title,
            summary: "",
            ingredients: [
                RecipeIngredient(
                    ingredient: Ingredient(name: "Rice", category: .grain),
                    quantity: 100,
                    unit: .grams,
                    role: .essential
                ),
            ],
            instructions: ["Cook."]
        )
    }

    // MARK: - Combining

    func test_combinesPrimaryAndSupplementarySources() async throws {
        let bundled = InMemoryRecipeRepository(recipes: [recipe("Bundled A"), recipe("Bundled B")])
        let saved = InMemorySavedRecipeRepository(recipes: [recipe("Saved A")])
        let composite = CompositeRecipeRepository(bundled: bundled, savedRecipes: saved)

        let all = try await composite.fetchAll()

        XCTAssertEqual(all.map(\.title), ["Bundled A", "Bundled B", "Saved A"])
    }

    func test_noSavedStore_behavesExactlyLikeBundledAlone() async throws {
        // This is the property that makes wiring the composite in today a
        // no-op for existing behaviour while saving is gated off.
        let recipes = [recipe("Bundled A"), recipe("Bundled B")]
        let bundled = InMemoryRecipeRepository(recipes: recipes)
        let composite = CompositeRecipeRepository(bundled: bundled, savedRecipes: nil)

        let viaComposite = try await composite.fetchAll()
        let viaBundled = try await bundled.fetchAll()

        XCTAssertEqual(viaComposite.map(\.id), viaBundled.map(\.id))
    }

    // MARK: - De-duplication

    func test_deduplicatesByRecipeID_firstOccurrenceWins() async throws {
        let shared = UUID()
        let bundled = InMemoryRecipeRepository(recipes: [recipe("From Bundled", id: shared)])
        let saved = InMemorySavedRecipeRepository(recipes: [recipe("From Saved", id: shared)])
        let composite = CompositeRecipeRepository(bundled: bundled, savedRecipes: saved)

        let all = try await composite.fetchAll()

        XCTAssertEqual(all.count, 1, "The same recipe id must not occupy two slots in a ranked list")
        XCTAssertEqual(all.first?.title, "From Bundled")
    }

    func test_deduplicationIsStableAndOrderPreserving() {
        let a = recipe("A"), b = recipe("B")
        let input = [a, b, a, b, a]

        let result = CompositeRecipeRepository.deduplicatedByID(input)

        XCTAssertEqual(result.map(\.id), [a.id, b.id])
    }

    // MARK: - Failure handling

    func test_primaryFailure_propagates() async {
        let bundled = FailingRecipeRepository()
        let composite = CompositeRecipeRepository(primary: bundled)

        do {
            _ = try await composite.fetchAll()
            XCTFail("Expected the primary failure to propagate")
        } catch {
            XCTAssertTrue(error is FailingRecipeRepository.Failure)
        }
    }

    func test_supplementaryFailure_degradesToPrimary_ratherThanFailing() async throws {
        // Signed out, offline, or rules not yet deployed. Losing saved
        // recipes must not take recommendations down with it.
        let bundled = InMemoryRecipeRepository(recipes: [recipe("Bundled A")])
        let saved = InMemorySavedRecipeRepository()
        saved.failure = SaveOnlineRecipeError.notAuthenticated
        let composite = CompositeRecipeRepository(bundled: bundled, savedRecipes: saved)

        let all = try await composite.fetchAll()

        XCTAssertEqual(all.map(\.title), ["Bundled A"])
        XCTAssertEqual(composite.lastSupplementaryFailure as? SaveOnlineRecipeError, .notAuthenticated)
    }

    func test_lastSupplementaryFailure_clearsOnASubsequentCleanRead() async throws {
        let bundled = InMemoryRecipeRepository(recipes: [recipe("Bundled A")])
        let saved = InMemorySavedRecipeRepository()
        saved.failure = SaveOnlineRecipeError.loadFailed
        let composite = CompositeRecipeRepository(bundled: bundled, savedRecipes: saved)

        _ = try await composite.fetchAll()
        XCTAssertNotNil(composite.lastSupplementaryFailure)

        saved.failure = nil
        _ = try await composite.fetchAll()
        XCTAssertNil(composite.lastSupplementaryFailure)
    }
}

/// A `RecipeRepository` that always fails, for the primary-error path.
private final class FailingRecipeRepository: RecipeRepository {
    struct Failure: Error {}

    func fetchAll() async throws -> [Recipe] {
        throw Failure()
    }
}
