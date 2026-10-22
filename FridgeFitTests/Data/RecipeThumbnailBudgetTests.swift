//
//  RecipeThumbnailBudgetTests.swift
//  FridgeFitTests
//
//  What the Recipes screen is allowed to spend on photos: a byte budget for
//  the decoded-thumbnail cache, a bound on how many decode at once, and
//  row-sized thumbnails for rows.
//
//  These assert the *configuration* and the *observable decoding behaviour*.
//  They never try to provoke an `NSCache` eviction: `NSCache` makes no promise
//  about which entry it drops, or when, so a test that depended on it would be
//  a flake rather than a regression test.
//

import UIKit
import XCTest
@testable import FridgeFit

private func pngBytes(width: CGFloat, height: CGFloat) -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
        UIColor.systemTeal.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }.pngData()!
}

/// Records how many decodes are in flight at once, from whatever thread the
/// task group runs them on.
private final class DecodeObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private var peak = 0
    private var started = 0

    func begin() {
        lock.withLock {
            active += 1
            started += 1
            peak = max(peak, active)
        }
    }

    func end() {
        lock.withLock { active -= 1 }
    }

    var peakConcurrent: Int { lock.withLock { peak } }
    var decodesStarted: Int { lock.withLock { started } }
}

final class RecipeThumbnailBudgetTests: XCTestCase {

    // MARK: - Cache memory ceiling

    func test_cache_boundsMemoryInBytes_notOnlyByCount() {
        let cache = RecipeThumbnailCache()

        XCTAssertEqual(cache.totalCostLimit, 32 * 1024 * 1024, "A byte budget, not just a count")
        XCTAssertEqual(cache.countLimit, 100, "The existing count bound is kept as a secondary limit")
    }

    func test_cacheBudget_isConfigurable() {
        let cache = RecipeThumbnailCache(countLimit: 7, totalCostLimit: 1234)

        XCTAssertEqual(cache.countLimit, 7)
        XCTAssertEqual(cache.totalCostLimit, 1234)
    }

    func test_cacheCost_isTheDecodedBitmapSize() throws {
        let image = try XCTUnwrap(RecipeThumbnailDecoder.thumbnail(from: pngBytes(width: 200, height: 100), maxPixelSize: 400))

        XCTAssertEqual(RecipeThumbnailCache.cost(of: image), 200 * 100 * 4, "width x height x RGBA")
    }

    /// The cost must follow the pixels. Measuring `size` would under-count a
    /// 3x image ninefold - exactly the images this cache holds.
    func test_cacheCost_measuresPixels_notPoints() throws {
        let bitmap = try XCTUnwrap(UIImage(data: pngBytes(width: 300, height: 300))?.cgImage)
        let scaled = UIImage(cgImage: bitmap, scale: 3, orientation: .up)

        XCTAssertEqual(scaled.size, CGSize(width: 100, height: 100), "Precondition: 100pt at 3x")
        XCTAssertEqual(RecipeThumbnailCache.cost(of: scaled), 300 * 300 * 4)
    }

    func test_cacheCost_isNeverZero() throws {
        let tiny = try XCTUnwrap(RecipeThumbnailDecoder.thumbnail(from: pngBytes(width: 1, height: 1)))

        XCTAssertGreaterThan(RecipeThumbnailCache.cost(of: tiny), 0, "A zero cost would be invisible to the budget")
    }

    func test_cache_storesAndReturnsTheSameImage_andRemoveEvictsIt() throws {
        let cache = RecipeThumbnailCache()
        let id = UUID()
        let image = try XCTUnwrap(RecipeThumbnailDecoder.thumbnail(from: pngBytes(width: 20, height: 20)))

        XCTAssertNil(cache.image(for: id), "Empty to begin with")
        cache.insert(image, for: id)
        XCTAssertIdentical(cache.image(for: id), image, "A hit returns the very image that was stored")

        cache.remove(id)
        XCTAssertNil(cache.image(for: id))
    }

    func test_cache_keepsEntriesSeparatePerRecipe() throws {
        let cache = RecipeThumbnailCache()
        let first = UUID()
        let second = UUID()
        let image = try XCTUnwrap(RecipeThumbnailDecoder.thumbnail(from: pngBytes(width: 20, height: 20)))

        cache.insert(image, for: first)

        XCTAssertNotNil(cache.image(for: first))
        XCTAssertNil(cache.image(for: second), "Removing or missing one id must not affect another")
    }

    // MARK: - Bounded decoding concurrency

    func test_decoding_neverExceedsTheConcurrencyBound() async {
        let observer = DecodeObserver()
        let data = Dictionary(uniqueKeysWithValues: (0 ..< 12).map { _ in (UUID(), pngBytes(width: 40, height: 40)) })

        let decoded = await RecipeThumbnailDecoder.thumbnails(from: data, maxConcurrent: 4) { bytes, limit in
            observer.begin()
            defer { observer.end() }
            // Holds the slot long enough for an unbounded implementation to
            // show itself; with a window of 4 the peak cannot pass 4.
            Thread.sleep(forTimeInterval: 0.03)
            return RecipeThumbnailDecoder.thumbnail(from: bytes, maxPixelSize: limit)
        }

        XCTAssertEqual(decoded.count, 12, "Every photo is still decoded")
        XCTAssertEqual(observer.decodesStarted, 12, "Each exactly once")
        XCTAssertLessThanOrEqual(observer.peakConcurrent, 4, "Bounded")
        XCTAssertGreaterThan(observer.peakConcurrent, 1, "...but not serialised one at a time")
    }

    func test_decoding_defaultBound_isTheDocumentedMaximum() async {
        let observer = DecodeObserver()
        let data = Dictionary(uniqueKeysWithValues: (0 ..< 20).map { _ in (UUID(), pngBytes(width: 40, height: 40)) })

        _ = await RecipeThumbnailDecoder.thumbnails(from: data) { bytes, limit in
            observer.begin()
            defer { observer.end() }
            Thread.sleep(forTimeInterval: 0.02)
            return RecipeThumbnailDecoder.thumbnail(from: bytes, maxPixelSize: limit)
        }

        XCTAssertEqual(RecipeThumbnailDecoder.maxConcurrentDecodes, 4)
        XCTAssertLessThanOrEqual(
            observer.peakConcurrent,
            RecipeThumbnailDecoder.maxConcurrentDecodes,
            "A 20-recipe collection must not decode 20 bitmaps at once"
        )
    }

    /// The point of the bound: peak concurrency is set by the window, not by
    /// how many recipes the user has saved.
    func test_decoding_peakDoesNotGrowWithTheCollection() async {
        func peak(forCount count: Int) async -> Int {
            let observer = DecodeObserver()
            let data = Dictionary(uniqueKeysWithValues: (0 ..< count).map { _ in (UUID(), pngBytes(width: 40, height: 40)) })
            _ = await RecipeThumbnailDecoder.thumbnails(from: data, maxConcurrent: 3) { bytes, limit in
                observer.begin()
                defer { observer.end() }
                Thread.sleep(forTimeInterval: 0.02)
                return RecipeThumbnailDecoder.thumbnail(from: bytes, maxPixelSize: limit)
            }
            return observer.peakConcurrent
        }

        let small = await peak(forCount: 6)
        let large = await peak(forCount: 48)

        XCTAssertLessThanOrEqual(small, 3)
        XCTAssertLessThanOrEqual(large, 3, "Eight times the recipes, same ceiling")
    }

    func test_decoding_mapsEachRecipeToItsOwnImage() async {
        let widths: [CGFloat] = [10, 20, 30, 40, 50, 60, 70]
        var data: [UUID: Data] = [:]
        var expected: [UUID: CGFloat] = [:]
        for width in widths {
            let id = UUID()
            data[id] = pngBytes(width: width, height: 10)
            expected[id] = width
        }

        let decoded = await RecipeThumbnailDecoder.thumbnails(from: data, maxConcurrent: 3)

        XCTAssertEqual(decoded.count, widths.count)
        for (id, width) in expected {
            XCTAssertEqual(decoded[id]?.size.width, width, "Each id keeps its own image under concurrency")
        }
    }

    func test_decoding_undecodableEntryIsDropped_withoutStallingTheRest() async {
        var data: [UUID: Data] = [:]
        let good = (0 ..< 6).map { _ in UUID() }
        for id in good { data[id] = pngBytes(width: 20, height: 20) }
        let bad = (0 ..< 3).map { _ in UUID() }
        for id in bad { data[id] = Data([0, 1, 2]) }

        let decoded = await RecipeThumbnailDecoder.thumbnails(from: data, maxConcurrent: 2)

        XCTAssertEqual(Set(decoded.keys), Set(good), "The good ones all came through")
        for id in bad {
            XCTAssertNil(decoded[id])
        }
    }

    func test_decoding_emptyInput_decodesNothing() async {
        let observer = DecodeObserver()

        let decoded = await RecipeThumbnailDecoder.thumbnails(from: [:]) { bytes, limit in
            observer.begin()
            defer { observer.end() }
            return RecipeThumbnailDecoder.thumbnail(from: bytes, maxPixelSize: limit)
        }

        XCTAssertTrue(decoded.isEmpty)
        XCTAssertEqual(observer.decodesStarted, 0)
    }

    // MARK: - Cancellation

    func test_cancellation_stopsDecodingTheRestOfTheCollection() async {
        let observer = DecodeObserver()
        let data = Dictionary(uniqueKeysWithValues: (0 ..< 60).map { _ in (UUID(), pngBytes(width: 40, height: 40)) })

        let task = Task {
            await RecipeThumbnailDecoder.thumbnails(from: data, maxConcurrent: 2) { bytes, limit in
                observer.begin()
                defer { observer.end() }
                Thread.sleep(forTimeInterval: 0.02)
                return RecipeThumbnailDecoder.thumbnail(from: bytes, maxPixelSize: limit)
            }
        }

        try? await Task.sleep(for: .milliseconds(60))
        task.cancel()
        _ = await task.value

        XCTAssertLessThan(
            observer.decodesStarted,
            data.count,
            "Leaving the screen must not pay for the photos nobody will see"
        )
    }

    // MARK: - Thumbnail sizing

    func test_listThumbnailsAreRowSized_andCostAFractionOfTheHero() throws {
        let stored = pngBytes(width: 800, height: 800)

        let listThumbnail = try XCTUnwrap(RecipeThumbnailDecoder.thumbnail(from: stored))
        let hero = try XCTUnwrap(RecipeThumbnailDecoder.thumbnail(from: stored, maxPixelSize: RecipeThumbnailDecoder.heroPixelSize))

        XCTAssertEqual(RecipeThumbnailDecoder.listPixelSize, 400, "132pt rows on a 3x screen")
        XCTAssertEqual(max(listThumbnail.size.width, listThumbnail.size.height), 400, "Decoded for the row, not the file")
        XCTAssertEqual(max(hero.size.width, hero.size.height), 800, "The hero still gets the full stored photo")
        XCTAssertLessThan(
            RecipeThumbnailCache.cost(of: listThumbnail),
            RecipeThumbnailCache.cost(of: hero) / 3,
            "A row thumbnail costs a quarter of the memory of a hero"
        )
    }

    func test_thumbnailDecoding_keepsAspectRatio() throws {
        let image = try XCTUnwrap(RecipeThumbnailDecoder.thumbnail(from: pngBytes(width: 800, height: 400)))

        XCTAssertEqual(image.size.width / image.size.height, 2, accuracy: 0.02)
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 400)
    }
}

// MARK: - Through the view model

@MainActor
final class RecipeThumbnailSizingThroughViewModelTests: XCTestCase {

    private func recipe(_ id: Int) -> Recipe {
        Recipe(
            id: SaveOnlineRecipeUseCase.savedRecipeID(forOnlineRecipeID: id),
            title: "Recipe \(id)",
            summary: "",
            ingredients: [RecipeIngredient(ingredient: Ingredient(name: "Rice"), quantity: 1, unit: .cups, role: .essential)],
            instructions: ["Cook."]
        )
    }

    private func viewModel(_ repository: SavedRecipeRepository) -> RecipeViewModel {
        RecipeViewModel(
            recipeRepository: InMemoryRecipeRepository(recipes: []),
            pantryRepository: InMemoryPantryRepository(),
            savedRecipeRepository: repository
        )
    }

    /// The list pays row prices; the hero pays full price, on demand, for the
    /// one recipe that is open.
    func test_listGetsRowSizedThumbnail_heroGetsFullSizeOnDemand() async throws {
        let repository = InMemorySavedRecipeRepository()
        let saved = recipe(1)
        try await repository.save(saved, sourceRecipeID: 1, imageData: pngBytes(width: 800, height: 800))
        let model = viewModel(repository)

        await model.loadRecipes()

        let listThumbnail = try XCTUnwrap(model.thumbnail(for: saved))
        XCTAssertEqual(max(listThumbnail.size.width, listThumbnail.size.height), 400, "The list decodes at row size")

        // Before the detail screen asks, the hero shows the row thumbnail
        // rather than nothing.
        XCTAssertIdentical(model.heroImage(for: saved), listThumbnail)

        await model.loadHeroImage(for: saved)

        let hero = try XCTUnwrap(model.heroImage(for: saved))
        XCTAssertEqual(max(hero.size.width, hero.size.height), 800, "The open recipe gets the full stored photo")
        XCTAssertNotIdentical(hero, listThumbnail)
    }

    func test_heroImage_isDecodedOnlyOnce() async throws {
        let repository = InMemorySavedRecipeRepository()
        let saved = recipe(2)
        try await repository.save(saved, sourceRecipeID: 2, imageData: pngBytes(width: 800, height: 800))
        let model = viewModel(repository)
        await model.loadRecipes()

        await model.loadHeroImage(for: saved)
        let first = try XCTUnwrap(model.heroImage(for: saved))
        await model.loadHeroImage(for: saved)

        XCTAssertIdentical(model.heroImage(for: saved), first, "A second visit reuses the decoded hero")
    }

    func test_heroImage_isDroppedWhenTheRecipeIsRemoved() async throws {
        let repository = InMemorySavedRecipeRepository()
        let saved = recipe(3)
        try await repository.save(saved, sourceRecipeID: 3, imageData: pngBytes(width: 800, height: 800))
        let model = viewModel(repository)
        await model.loadRecipes()
        await model.loadHeroImage(for: saved)
        XCTAssertNotNil(model.heroImage(for: saved))

        await model.removeSavedRecipe(saved)

        XCTAssertNil(model.heroImage(for: saved))
        XCTAssertNil(model.thumbnail(for: saved))
    }

    func test_heroImage_isANoOpForARecipeWithNoStoredPhoto() async throws {
        let repository = InMemorySavedRecipeRepository()
        let saved = recipe(4)
        try await repository.save(saved, sourceRecipeID: 4, imageData: nil)
        let model = viewModel(repository)
        await model.loadRecipes()

        await model.loadHeroImage(for: saved)

        XCTAssertNil(model.heroImage(for: saved))
    }
}
