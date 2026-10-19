//
//  MockSubstitutionService.swift
//  FridgeFit
//

import Foundation

/// Test double / preview double for `SubstitutionService`.
///
/// Returns whatever `result` is set to, reports whatever `availability` is
/// set to, and records the last request it was asked about so tests can
/// assert on what `GetIngredientSubstitutionsUseCase` actually sent - no
/// model execution, no device requirement, fully deterministic.
///
/// This is how the substitution flow is tested at all now that the provider
/// is on-device: Apple Intelligence can't run in the simulator, so every
/// test above `AppleSubstitutionService` drives this instead.
nonisolated final class MockSubstitutionService: SubstitutionService {
    var result: Result<[RawSubstitutionSuggestion], Error>
    var availability: AppleIntelligenceAvailability
    private(set) var requestCount = 0
    private(set) var lastRequest: SubstitutionRequest?

    init(
        result: Result<[RawSubstitutionSuggestion], Error> = .success([]),
        availability: AppleIntelligenceAvailability = .available
    ) {
        self.result = result
        self.availability = availability
    }

    func suggestSubstitutions(for request: SubstitutionRequest) async throws -> [RawSubstitutionSuggestion] {
        requestCount += 1
        lastRequest = request
        return try result.get()
    }
}
