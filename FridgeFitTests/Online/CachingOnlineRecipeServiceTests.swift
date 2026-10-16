//
//  CachingOnlineRecipeServiceTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class CachingOnlineRecipeServiceTests: XCTestCase {
    private let criteria = OnlineRecipeSearchCriteria(pantryIngredientNames: ["Garlic", "chicken"], preferences: .default)

    func test_freshSuccess_isReturned_andCached() async throws {
        let wrapped = MockOnlineRecipeService(result: .success([OnlineRecipeFixtures.match()]))
        let cache = InMemoryOnlineRecipeCacheStore()
        let service = CachingOnlineRecipeService(wrapping: wrapped, cache: cache)

        let result = try await service.searchRecipes(matching: criteria)

        XCTAssertEqual(result.map(\.id), [1])
        XCTAssertFalse(result[0].isFromCache)
        XCTAssertNotNil(cache.loadMatches(forKey: CachingOnlineRecipeService.cacheKey(for: criteria)))
    }

    func test_networkFailure_servesCache_markedAsCached() async throws {
        let wrapped = MockOnlineRecipeService(result: .success([OnlineRecipeFixtures.match()]))
        let service = CachingOnlineRecipeService(wrapping: wrapped, cache: InMemoryOnlineRecipeCacheStore())
        _ = try await service.searchRecipes(matching: criteria)

        wrapped.result = .failure(.network)
        let offline = try await service.searchRecipes(matching: criteria)

        XCTAssertEqual(offline.map(\.id), [1])
        XCTAssertTrue(offline.allSatisfy(\.isFromCache))
    }

    func test_networkFailure_withoutCache_rethrows() async {
        let service = CachingOnlineRecipeService(
            wrapping: MockOnlineRecipeService(result: .failure(.timeout)),
            cache: InMemoryOnlineRecipeCacheStore()
        )
        do {
            _ = try await service.searchRecipes(matching: criteria)
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? OnlineRecipeSearchError, .timeout)
        }
    }

    func test_nonConnectivityFailure_neverServesCache() async throws {
        let wrapped = MockOnlineRecipeService(result: .success([OnlineRecipeFixtures.match()]))
        let service = CachingOnlineRecipeService(wrapping: wrapped, cache: InMemoryOnlineRecipeCacheStore())
        _ = try await service.searchRecipes(matching: criteria)

        wrapped.result = .failure(.unauthorized)
        do {
            _ = try await service.searchRecipes(matching: criteria)
            XCTFail("A rejected key must surface, not be hidden by cached data")
        } catch {
            XCTAssertEqual(error as? OnlineRecipeSearchError, .unauthorized)
        }
    }

    func test_emptyResult_isNotCached() async throws {
        let cache = InMemoryOnlineRecipeCacheStore()
        let service = CachingOnlineRecipeService(wrapping: MockOnlineRecipeService(result: .success([])), cache: cache)

        _ = try await service.searchRecipes(matching: criteria)

        XCTAssertTrue(cache.stored.isEmpty)
    }

    func test_cacheKey_ignoresOrderAndCase_butNotFilters() {
        let reordered = OnlineRecipeSearchCriteria(pantryIngredientNames: ["CHICKEN", " garlic "], preferences: .default)
        XCTAssertEqual(CachingOnlineRecipeService.cacheKey(for: criteria), CachingOnlineRecipeService.cacheKey(for: reordered))

        let filtered = OnlineRecipeSearchCriteria(
            pantryIngredientNames: criteria.pantryIngredientNames,
            preferences: OnlineRecipePreferences(diet: .vegan)
        )
        XCTAssertNotEqual(CachingOnlineRecipeService.cacheKey(for: criteria), CachingOnlineRecipeService.cacheKey(for: filtered))
    }

    func test_fileCacheStore_roundTripsThroughDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("online-cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        OnlineRecipeCacheStore(fileURL: url).save([OnlineRecipeFixtures.match(id: 42)], forKey: "k")
        let loaded = OnlineRecipeCacheStore(fileURL: url).loadMatches(forKey: "k")

        XCTAssertEqual(loaded?.map(\.id), [42])
    }
}
