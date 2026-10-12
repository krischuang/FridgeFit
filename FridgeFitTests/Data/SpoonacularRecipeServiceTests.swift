//
//  SpoonacularRecipeServiceTests.swift
//  FridgeFitTests
//
//  Exercises the real service against a stubbed URLProtocol - no network
//  access, no Spoonacular quota consumed.
//

import XCTest
@testable import FridgeFit

private final class SpoonacularStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
final class SpoonacularRecipeServiceTests: XCTestCase {
    override func tearDown() {
        SpoonacularStubURLProtocol.handler = nil
        SpoonacularStubURLProtocol.lastRequest = nil
        super.tearDown()
    }

    private func makeService() -> SpoonacularRecipeService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpoonacularStubURLProtocol.self]
        return SpoonacularRecipeService(
            configuration: SpoonacularConfiguration(apiKey: "test-key"),
            urlSession: URLSession(configuration: configuration)
        )
    }

    private func respond(status: Int, body: String) {
        SpoonacularStubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
    }

    private func criteria(_ preferences: OnlineRecipePreferences = .default) -> OnlineRecipeSearchCriteria {
        OnlineRecipeSearchCriteria(pantryIngredientNames: ["garlic", "chicken"], preferences: preferences)
    }

    private func queryValue(_ name: String, in url: URL?) -> String? {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return components.queryItems?.first { $0.name == name }?.value
    }

    // MARK: - Request building

    func test_requestURL_includesPantryAndAllFilters() {
        let preferences = OnlineRecipePreferences(diet: .vegetarian, intolerances: [.peanut, .dairy], maxReadyTimeMinutes: 30)
        let url = SpoonacularRecipeService.requestURL(for: criteria(preferences), apiKey: "abc")

        XCTAssertEqual(queryValue("apiKey", in: url), "abc")
        XCTAssertEqual(queryValue("includeIngredients", in: url), "garlic,chicken")
        XCTAssertEqual(queryValue("diet", in: url), "Vegetarian")
        XCTAssertEqual(queryValue("intolerances", in: url), "dairy,peanut")
        XCTAssertEqual(queryValue("maxReadyTime", in: url), "30")
        XCTAssertEqual(queryValue("number", in: url), "30")
        XCTAssertEqual(queryValue("addRecipeInstructions", in: url), "true")
        XCTAssertEqual(queryValue("fillIngredients", in: url), "true")
    }

    func test_requestURL_omitsUnsetFilters() {
        let url = SpoonacularRecipeService.requestURL(for: criteria(), apiKey: "abc")

        XCTAssertNil(queryValue("diet", in: url))
        XCTAssertNil(queryValue("intolerances", in: url))
        XCTAssertNil(queryValue("maxReadyTime", in: url))
    }

    func test_requestURL_clampsResultLimitToSpoonacularMaximum() {
        var tooMany = criteria()
        tooMany.resultLimit = 500
        XCTAssertEqual(queryValue("number", in: SpoonacularRecipeService.requestURL(for: tooMany, apiKey: "k")), "100")
    }

    // MARK: - Parsing

    func test_parseMatches_mapsRecipeFields() throws {
        let matches = try SpoonacularRecipeService.parseMatches(from: Data(OnlineRecipeFixtures.searchResponseJSON.utf8))
        let match = try XCTUnwrap(matches.first)

        XCTAssertEqual(match.recipe.id, 716429)
        XCTAssertEqual(match.recipe.readyInMinutes, 45)
        XCTAssertEqual(match.recipe.summary, "A quick pasta & cheese dish.")
        XCTAssertEqual(match.recipe.steps, ["Boil the pasta.", "Melt the butter with garlic."])
        XCTAssertEqual(match.recipe.sourceURL?.absoluteString, "https://example.com/pasta")
        XCTAssertEqual(match.usedIngredientNames, ["garlic"])
        XCTAssertEqual(match.missedIngredients.map(\.name), ["pasta", "butter"])
    }

    func test_parseMatches_mapsUnits_andFlagsServingsAsUncertain() throws {
        let recipe = try XCTUnwrap(SpoonacularRecipeService.parseMatches(from: Data(OnlineRecipeFixtures.searchResponseJSON.utf8)).first?.recipe)
        let byName = Dictionary(uniqueKeysWithValues: recipe.ingredients.map { ($0.name, $0) })

        XCTAssertEqual(byName["butter"]?.unit, .tablespoons)
        XCTAssertEqual(byName["pasta"]?.unit, .kilograms)
        XCTAssertNil(byName["garlic"]?.unit, "\"cloves\" has no MeasurementUnit - kept as raw text, not guessed")
        XCTAssertEqual(byName["garlic"]?.formattedQuantity, "5 cloves")
        XCTAssertEqual(byName["spring onions"]?.quantityIsUncertain, true)
    }

    func test_parseMatches_detectsIntolerancesFromIngredients() throws {
        let recipe = try XCTUnwrap(SpoonacularRecipeService.parseMatches(from: Data(OnlineRecipeFixtures.searchResponseJSON.utf8)).first?.recipe)

        XCTAssertEqual(recipe.containsIntolerances?.contains(.dairy), true)
        XCTAssertEqual(recipe.containsIntolerances?.contains(.gluten), true)
        XCTAssertEqual(recipe.containsIntolerances?.contains(.peanut), false)
    }

    func test_parseMatches_invalidJSON_throwsMalformedResponse() {
        XCTAssertThrowsError(try SpoonacularRecipeService.parseMatches(from: Data("not json".utf8))) { error in
            XCTAssertEqual(error as? OnlineRecipeSearchError, .malformedResponse)
        }
    }

    func test_parseMatches_recipeWithoutIngredients_isUnverified() throws {
        let json = #"{"results":[{"id":1,"title":"Mystery"}]}"#
        let recipe = try XCTUnwrap(SpoonacularRecipeService.parseMatches(from: Data(json.utf8)).first?.recipe)
        XCTAssertNil(recipe.containsIntolerances)
    }

    // MARK: - HTTP

    func test_search_success_returnsMatches_andSendsKey() async throws {
        respond(status: 200, body: OnlineRecipeFixtures.searchResponseJSON)

        let matches = try await makeService().searchRecipes(matching: criteria())

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(queryValue("apiKey", in: SpoonacularStubURLProtocol.lastRequest?.url), "test-key")
    }

    func test_search_401_throwsUnauthorized() async {
        respond(status: 401, body: "{}")
        await assertSearchThrows(.unauthorized)
    }

    func test_search_402_throwsQuotaExceeded() async {
        respond(status: 402, body: "{}")
        await assertSearchThrows(.quotaExceeded)
    }

    func test_search_500_throwsProviderUnavailable() async {
        respond(status: 500, body: "{}")
        await assertSearchThrows(.providerUnavailable)
    }

    func test_search_connectionFailure_throwsNetwork() async {
        SpoonacularStubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await assertSearchThrows(.network)
    }

    func test_search_timeout_throwsTimeout() async {
        SpoonacularStubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        await assertSearchThrows(.timeout)
    }

    func test_unconfiguredService_throwsNotConfigured() async {
        do {
            _ = try await UnconfiguredOnlineRecipeService().searchRecipes(matching: criteria())
            XCTFail("Expected notConfigured")
        } catch {
            XCTAssertEqual(error as? OnlineRecipeSearchError, .notConfigured)
        }
    }

    private func assertSearchThrows(_ expected: OnlineRecipeSearchError, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await makeService().searchRecipes(matching: criteria())
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? OnlineRecipeSearchError, expected, file: file, line: line)
        }
    }
}
