//
//  SavedRecipePhotoTests.swift
//  FridgeFitTests
//
//  Saved recipes keep their photo locally: downloaded once at save time,
//  stored in SwiftData, and read back without the network.
//

import SwiftData
import UIKit
import XCTest
@testable import FridgeFit

// MARK: - Doubles

private final class StubImageDownloader: RecipeImageDownloading {
    var result: Data?
    private(set) var requestedURLs: [URL] = []

    init(result: Data?) {
        self.result = result
    }

    func imageData(from url: URL) async -> Data? {
        requestedURLs.append(url)
        return result
    }
}

private final class ImageStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func pngData(width: CGFloat, height: CGFloat) -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
        UIColor.systemGreen.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }.pngData()!
}

private let photoURL = URL(string: "https://img.spoonacular.com/recipes/716429-556x370.jpg")!

// MARK: - SwiftData store

@MainActor
final class SavedRecipePhotoTests: XCTestCase {
    private var container: PersistenceContainer!
    private var owner: String? = "owner-a"
    private var repository: SwiftDataSavedRecipeRepository!

    override func setUp() async throws {
        try await super.setUp()
        container = try PersistenceContainer(storage: .inMemory)
        repository = makeRepository()
    }

    override func tearDown() async throws {
        ImageStubURLProtocol.handler = nil
        repository = nil
        container = nil
        try await super.tearDown()
    }

    private func makeRepository() -> SwiftDataSavedRecipeRepository {
        SwiftDataSavedRecipeRepository(
            store: SwiftDataSavedRecipeStore(context: container.mainContext, ownerIDProvider: { [unowned self] in self.owner })
        )
    }

    private func recipe(id: Int = 716429, imageURL: URL? = photoURL) -> Recipe {
        Recipe(
            id: SaveOnlineRecipeUseCase.savedRecipeID(forOnlineRecipeID: id),
            title: "Garlic Pasta",
            summary: "Quick.",
            ingredients: [RecipeIngredient(ingredient: Ingredient(name: "Pasta"), quantity: 200, unit: .grams, role: .essential)],
            instructions: ["Boil."],
            imageURL: imageURL
        )
    }

    private func onlineRecipe(id: Int = 9, imageURL: URL? = photoURL) -> OnlineRecipe {
        var online = OnlineRecipeFixtures.recipe(id: id, title: "Online Bowl")
        online.imageURL = imageURL
        return online
    }

    func test_store_savesPhotoAndURL_andReadsThemBack() async throws {
        let photo = Data([1, 2, 3])

        try await repository.save(recipe(), sourceRecipeID: 716429, imageData: photo)

        let loaded = try await repository.fetchAll()
        XCTAssertEqual(loaded.first?.imageURL, photoURL)
        let stored = try await repository.imageData(forRecipeID: recipe().id)
        XCTAssertEqual(stored, photo)
    }

    func test_store_resaveWithoutPhoto_keepsExistingPhoto_newPhotoReplacesIt() async throws {
        try await repository.save(recipe(), sourceRecipeID: 716429, imageData: Data([1]))
        try await repository.save(recipe(), sourceRecipeID: 716429, imageData: nil)
        let kept = try await repository.imageData(forRecipeID: recipe().id)
        XCTAssertEqual(kept, Data([1]))

        try await repository.save(recipe(), sourceRecipeID: 716429, imageData: Data([2]))
        let replaced = try await repository.imageData(forRecipeID: recipe().id)
        XCTAssertEqual(replaced, Data([2]))
    }

    func test_store_photoIsOwnerScoped_andRemovedWithRecipe() async throws {
        try await repository.save(recipe(), sourceRecipeID: 716429, imageData: Data([7]))

        owner = "owner-b"
        let otherOwners = try await repository.imageData(forRecipeID: recipe().id)
        XCTAssertNil(otherOwners)

        owner = "owner-a"
        try await repository.remove(id: recipe().id)
        let afterRemove = try await repository.imageData(forRecipeID: recipe().id)
        XCTAssertNil(afterRemove)
    }

    // MARK: - Use case

    func test_useCase_downloadsPhotoOnce_andStoresIt() async throws {
        let downloader = StubImageDownloader(result: Data([9, 9]))
        let useCase = SaveOnlineRecipeUseCase(repository: repository, imageDownloader: downloader)

        let saved = try await useCase.execute(onlineRecipe())

        XCTAssertEqual(downloader.requestedURLs, [photoURL])
        XCTAssertEqual(saved.imageURL, photoURL)
        let stored = try await repository.imageData(forRecipeID: saved.id)
        XCTAssertEqual(stored, Data([9, 9]))
    }

    func test_useCase_failedDownload_stillSavesRecipe() async throws {
        let useCase = SaveOnlineRecipeUseCase(repository: repository, imageDownloader: StubImageDownloader(result: nil))

        let saved = try await useCase.execute(onlineRecipe())

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.map(\.id), [saved.id])
        let stored = try await repository.imageData(forRecipeID: saved.id)
        XCTAssertNil(stored)
    }

    func test_useCase_noImageURL_neverDownloads() async throws {
        let downloader = StubImageDownloader(result: Data([1]))

        _ = try await SaveOnlineRecipeUseCase(repository: repository, imageDownloader: downloader).execute(onlineRecipe(imageURL: nil))

        XCTAssertTrue(downloader.requestedURLs.isEmpty)
    }

    // MARK: - View model

    func test_viewModel_exposesStoredPhoto_afterSave_reload_andRemove() async throws {
        let downloader = StubImageDownloader(result: Data([4, 2]))
        let viewModel = RecipeViewModel(
            recipeRepository: InMemoryRecipeRepository(recipes: []),
            pantryRepository: InMemoryPantryRepository(),
            savedRecipeRepository: repository,
            imageDownloader: downloader
        )
        await viewModel.loadRecipes()
        await viewModel.saveOnlineRecipe(onlineRecipe(id: 5))
        let saved = try XCTUnwrap(viewModel.savedRecipes.first)
        XCTAssertEqual(viewModel.imageData(for: saved), Data([4, 2]))

        // As after relaunch: a fresh view model reads the photo from the store only.
        let reloaded = RecipeViewModel(
            recipeRepository: InMemoryRecipeRepository(recipes: []),
            pantryRepository: InMemoryPantryRepository(),
            savedRecipeRepository: makeRepository()
        )
        await reloaded.loadRecipes()
        XCTAssertEqual(reloaded.imageData(for: saved), Data([4, 2]))

        await viewModel.removeSavedRecipe(saved)
        XCTAssertNil(viewModel.imageData(for: saved))
    }

    // MARK: - Downloader

    private func makeDownloader() -> URLSessionRecipeImageDownloader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageStubURLProtocol.self]
        return URLSessionRecipeImageDownloader(session: URLSession(configuration: configuration))
    }

    private func respond(status: Int, mimeType: String, body: Data) {
        ImageStubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": mimeType])!
            return (response, body)
        }
    }

    func test_downloader_validImage_isDownscaledJPEG() async throws {
        respond(status: 200, mimeType: "image/png", body: pngData(width: 2000, height: 1000))

        let downloaded = await makeDownloader().imageData(from: photoURL)
        let data = try XCTUnwrap(downloaded)
        let image = try XCTUnwrap(UIImage(data: data))

        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 800)
        XCTAssertEqual(image.size.width / image.size.height, 2, accuracy: 0.01, "Aspect ratio is kept")
        XCTAssertEqual(data.prefix(2), Data([0xFF, 0xD8]), "Stored as JPEG")
    }

    func test_downloader_rejectsNonImage_errors_andNonHTTPS() async {
        respond(status: 200, mimeType: "text/html", body: Data("<html>".utf8))
        let html = await makeDownloader().imageData(from: photoURL)
        XCTAssertNil(html)

        respond(status: 404, mimeType: "image/jpeg", body: pngData(width: 10, height: 10))
        let notFound = await makeDownloader().imageData(from: photoURL)
        XCTAssertNil(notFound)

        respond(status: 200, mimeType: "image/png", body: pngData(width: 10, height: 10))
        let insecure = await makeDownloader().imageData(from: URL(string: "http://img.spoonacular.com/x.png")!)
        XCTAssertNil(insecure)
    }

    func test_downscale_leavesSmallImagesAtTheirSize() async throws {
        let data = try XCTUnwrap(URLSessionRecipeImageDownloader.downscaledJPEG(from: pngData(width: 300, height: 200)))
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(image.size, CGSize(width: 300, height: 200))
    }
}
