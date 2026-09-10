//
//  MockSubstitutionService.swift
//  FridgeFit
//

import Foundation

/// Test double / preview double for `SubstitutionService`.
///
/// Returns whatever `result` is set to, and records the last request it
/// was asked about so tests can assert on what
/// `GetIngredientSubstitutionsUseCase` actually sent - no network, no live
/// provider, fully deterministic.
final class MockSubstitutionService: SubstitutionService {
    var result: Result<[RawSubstitutionSuggestion], Error>
    private(set) var requestCount = 0
    private(set) var lastRequest: SubstitutionRequest?

    init(result: Result<[RawSubstitutionSuggestion], Error> = .success([])) {
        self.result = result
    }

    func suggestSubstitutions(for request: SubstitutionRequest) async throws -> [RawSubstitutionSuggestion] {
        requestCount += 1
        lastRequest = request
        return try result.get()
    }
}
