//
//  SavedRecipeThumbnailTests.swift
//  FridgeFitTests
//
//  The Recipes screen reads saved photos in batches, decodes them off the
//  main thread, and caches the decoded thumbnails.
//

import UIKit
import XCTest
@testable import FridgeFit

private func png(width: CGFloat, height: CGFloat) -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
        UIColor.systemOrange.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }.pngData()!
}

/// A store with no batch query of its own - like Firestore - to prove the
/// protocol's fallback.
private final class SingleLookupSavedRecipeRepository: SavedRecipeRepository {
    var images: [UUID: Data] = [:]
    private(set) var singleLookups: [UUID] = []

    func fetchAll() async throws -> [Recipe] { [] }
    func save(_ recipe: Recipe, sourceRecipeID: Int) async throws {}
    func remove(id: UUID) async throws {}
    func imageData(forRecipeID id: UUID) async throws -> Data? {
        singleLookups.append(id)
        return images[id]
    }
}

@MainActor
final class SavedRecipeThumbnailTests: XCTestCase {

    private func recipe(_ id: Int) -> Recipe {
        Recipe(
            id: SaveOnlineRecipeUseCase.savedRecipeID(forOnlineRecipeID: id),
            title: "Recipe \(id)",
            summary: "",
            ingredients: [RecipeIngredient(ingredient: Ingredient(name: "Rice"), quantity: 1, unit: .cups, role: .essential)],
            instructions: ["Cook."]
        )
    }

    private func store(photos: [Int: Data], without: [Int] = []) async throws -> InMemorySavedRecipeRepository {
        let repository = InMemorySavedRecipeRepository()
        for (id, data) in photos {
            try await repository.save(recipe(id), sourceRecipeID: id, imageData: data)
        }
        for id in without {
            try await repository.save(recipe(id), sourceRecipeID: id, imageData: nil)
        }
        return repository
    }

    private func viewModel(_ repository: SavedRecipeRepository, cache: RecipeThumbnailCache = RecipeThumbnailCache()) -> RecipeViewModel {
        RecipeViewModel(
            recipeRepository: InMemoryRecipeRepository(recipes: []),
            pantryRepository: InMemoryPantryRepository(),
            savedRecipeRepository: repository,
            thumbnailCache: cache
        )
    }

    // MARK: - Batching

    func test_load_readsAllPhotosInOneBatchRequest() async throws {
        let repository = try await store(photos: [1: png(width: 10, height: 10), 2: png(width: 10, height: 10), 3: png(width: 10, height: 10)])
        let model = viewModel(repository)

        await model.loadRecipes()

        XCTAssertEqual(repository.batchImageRequests.count, 1)
        XCTAssertEqual(Set(repository.batchImageRequests[0]), Set([1, 2, 3].map { recipe($0).id }))
        XCTAssertEqual(model.savedRecipeThumbnails.count, 3)
    }

    // MARK: - Caching

    func test_reload_reusesCachedThumbnails_withoutReadingTheStoreAgain() async throws {
        let repository = try await store(photos: [1: png(width: 10, height: 10)])
        let model = viewModel(repository)

        await model.loadRecipes()
        await model.loadRecipes()

        XCTAssertEqual(repository.batchImageRequests.count, 1, "Second load is served from the thumbnail cache")
        XCTAssertNotNil(model.thumbnail(for: recipe(1)))
    }

    func test_reload_doesNotAskAgainForRecipesKnownToHaveNoPhoto() async throws {
        let repository = try await store(photos: [:], without: [7])
        let model = viewModel(repository)

        await model.loadRecipes()
        await model.loadRecipes()

        XCTAssertEqual(repository.batchImageRequests.count, 1)
        XCTAssertNil(model.thumbnail(for: recipe(7)))
    }

    func test_cacheIsSharedAcrossViewModels() async throws {
        let cache = RecipeThumbnailCache()
        let repository = try await store(photos: [1: png(width: 10, height: 10)])

        await viewModel(repository, cache: cache).loadRecipes()
        let second = viewModel(repository, cache: cache)
        await second.loadRecipes()

        XCTAssertEqual(repository.batchImageRequests.count, 1)
        XCTAssertNotNil(second.thumbnail(for: recipe(1)))
    }

    // MARK: - Decoding

    func test_decoder_producesDecodedThumbnail_withinPixelLimit() throws {
        let image = try XCTUnwrap(RecipeThumbnailDecoder.thumbnail(from: png(width: 1600, height: 800), maxPixelSize: 400))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 400)
        XCTAssertEqual(image.size.width / image.size.height, 2, accuracy: 0.02)
    }

    func test_decoder_rejectsInvalidData() {
        XCTAssertNil(RecipeThumbnailDecoder.thumbnail(from: Data([1, 2, 3])))
    }

    func test_batchDecode_dropsUndecodableEntries() async {
        let good = UUID()
        let bad = UUID()

        let thumbnails = await RecipeThumbnailDecoder.thumbnails(from: [good: png(width: 20, height: 20), bad: Data([0])])

        XCTAssertEqual(Set(thumbnails.keys), [good])
    }

    // MARK: - Protocol fallback

    func test_storesWithoutBatchQuery_fallBackToSingleLookups() async throws {
        let repository = SingleLookupSavedRecipeRepository()
        let a = UUID()
        let b = UUID()
        repository.images = [a: Data([1])]

        let result = try await repository.imageData(forRecipeIDs: [a, b])

        XCTAssertEqual(result, [a: Data([1])])
        XCTAssertEqual(repository.singleLookups, [a, b])
    }
}
