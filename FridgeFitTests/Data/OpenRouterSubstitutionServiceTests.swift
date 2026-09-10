//
//  OpenRouterSubstitutionServiceTests.swift
//  FridgeFitTests
//
//  Exercises the real service against a stubbed URLProtocol - no network
//  access, no live OpenRouter quota consumed.
//

import XCTest
@testable import FridgeFit

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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

final class OpenRouterSubstitutionServiceTests: XCTestCase {
    private func makeService() -> OpenRouterSubstitutionService {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StubURLProtocol.self]
        let configuration = OpenRouterConfiguration(apiKey: "test-key", model: "test-model", referer: "https://example.com", appTitle: "FridgeFit Tests")
        return OpenRouterSubstitutionService(configuration: configuration, urlSession: URLSession(configuration: sessionConfiguration))
    }

    private func sampleRequest() -> SubstitutionRequest {
        SubstitutionRequest(
            recipeID: UUID(),
            recipeTitle: "Creamy Pasta",
            targetIngredientName: "Cream",
            requiredQuantity: 200,
            requiredUnit: .milliliters,
            role: .essential,
            pantryIngredients: [],
            feasibilityStatus: .notMakeable
        )
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func test_suggestSubstitutions_successfulResponse_decodesRawSuggestions_andSendsAuthHeader() async throws {
        var capturedRequest: URLRequest?
        StubURLProtocol.handler = { request in
            capturedRequest = request
            let body = #"{"choices": [{"message": {"role": "assistant", "content": "{\"suggestions\": [{\"ingredientName\": \"Milk\", \"suggestedQuantity\": null, \"suggestedUnit\": null, \"confidence\": null, \"explanation\": \"Thins the sauce.\", \"limitations\": null}]}"}}]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body.data(using: .utf8)!)
        }

        let suggestions = try await makeService().suggestSubstitutions(for: sampleRequest())

        XCTAssertEqual(suggestions.first?.ingredientName, "Milk")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
    }

    func test_suggestSubstitutions_rateLimited_throwsRateLimited() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await makeService().suggestSubstitutions(for: sampleRequest())
            XCTFail("Expected rateLimited error")
        } catch {
            XCTAssertEqual(error as? SubstitutionServiceError, .rateLimited)
        }
    }

    func test_suggestSubstitutions_serverError_throwsProviderUnavailable() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await makeService().suggestSubstitutions(for: sampleRequest())
            XCTFail("Expected providerUnavailable error")
        } catch {
            XCTAssertEqual(error as? SubstitutionServiceError, .providerUnavailable)
        }
    }

    func test_suggestSubstitutions_malformedBody_throwsMalformedResponse() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "not even json".data(using: .utf8)!)
        }

        do {
            _ = try await makeService().suggestSubstitutions(for: sampleRequest())
            XCTFail("Expected malformedResponse error")
        } catch {
            XCTAssertEqual(error as? SubstitutionServiceError, .malformedResponse)
        }
    }

    func test_suggestSubstitutions_timeout_throwsTimeout() async {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }

        do {
            _ = try await makeService().suggestSubstitutions(for: sampleRequest())
            XCTFail("Expected timeout error")
        } catch {
            XCTAssertEqual(error as? SubstitutionServiceError, .timeout)
        }
    }

    func test_suggestSubstitutions_networkError_throwsNetwork() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        do {
            _ = try await makeService().suggestSubstitutions(for: sampleRequest())
            XCTFail("Expected network error")
        } catch {
            XCTAssertEqual(error as? SubstitutionServiceError, .network)
        }
    }

    func test_unconfiguredSubstitutionService_alwaysThrowsNotConfigured() async {
        do {
            _ = try await UnconfiguredSubstitutionService().suggestSubstitutions(for: sampleRequest())
            XCTFail("Expected notConfigured error")
        } catch {
            XCTAssertEqual(error as? SubstitutionServiceError, .notConfigured)
        }
    }
}
