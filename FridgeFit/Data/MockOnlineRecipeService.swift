//
//  MockOnlineRecipeService.swift
//  FridgeFit
//

import Foundation

/// Test/preview double for `OnlineRecipeService`. Returns a fixed result
/// and records every criteria it was asked with.
nonisolated final class MockOnlineRecipeService: OnlineRecipeService {
    var result: Result<[OnlineRecipeMatch], OnlineRecipeSearchError>
    private(set) var receivedCriteria: [OnlineRecipeSearchCriteria] = []

    init(result: Result<[OnlineRecipeMatch], OnlineRecipeSearchError>) {
        self.result = result
    }

    func searchRecipes(matching criteria: OnlineRecipeSearchCriteria) async throws -> [OnlineRecipeMatch] {
        receivedCriteria.append(criteria)
        return try result.get()
    }
}
