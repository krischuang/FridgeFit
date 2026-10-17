//
//  OpenRouterSubstitutionService.swift
//  FridgeFit
//

import Foundation

/// Production `SubstitutionService` backed by OpenRouter's OpenAI-compatible
/// chat completions API.
///
/// Only ever returns `RawSubstitutionSuggestion`s - untrusted candidates.
/// Nothing here decides pantry availability; that's
/// `SubstitutionSuggestionValidator`'s job, downstream in
/// `GetIngredientSubstitutionsUseCase`.
nonisolated final class OpenRouterSubstitutionService: SubstitutionService {
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private static let timeoutInterval: TimeInterval = 20

    private let configuration: OpenRouterConfiguration
    private let urlSession: URLSession

    init(configuration: OpenRouterConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    func suggestSubstitutions(for request: SubstitutionRequest) async throws -> [RawSubstitutionSuggestion] {
        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = Self.timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        if let referer = configuration.referer {
            urlRequest.setValue(referer, forHTTPHeaderField: "HTTP-Referer")
        }
        if let appTitle = configuration.appTitle {
            urlRequest.setValue(appTitle, forHTTPHeaderField: "X-Title")
        }

        let body = SubstitutionPromptBuilder.chatCompletionBody(for: request, model: configuration.model)
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: urlRequest)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw SubstitutionServiceError.timeout
        } catch is URLError {
            throw SubstitutionServiceError.network
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SubstitutionServiceError.network
        }
        if httpResponse.statusCode == 429 {
            throw SubstitutionServiceError.rateLimited
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw SubstitutionServiceError.providerUnavailable
        }

        guard
            let completion = try? JSONDecoder().decode(OpenRouterChatCompletionResponse.self, from: data),
            let content = completion.choices.first?.message.content
        else {
            throw SubstitutionServiceError.malformedResponse
        }

        return try SubstitutionResponseParser.parseSuggestions(fromModelOutput: content)
    }
}

/// Used when no OpenRouter API key is configured locally, so the app fails
/// with a clear, actionable error instead of crashing or silently sending
/// an empty credential.
nonisolated struct UnconfiguredSubstitutionService: SubstitutionService {
    func suggestSubstitutions(for request: SubstitutionRequest) async throws -> [RawSubstitutionSuggestion] {
        throw SubstitutionServiceError.notConfigured
    }
}
