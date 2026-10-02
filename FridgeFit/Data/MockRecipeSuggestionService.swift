//
//  MockRecipeSuggestionService.swift
//  FridgeFit
//

import Foundation

/// Test double / preview double for `RecipeSuggestionService`.
///
/// Records the pantry it was handed so tests can assert that the real pantry
/// - and only the real pantry - is what gets sent to the model.
final class MockRecipeSuggestionService: RecipeSuggestionService {
    var result: Result<[RawRecipeSuggestion], Error>
    var availability: AppleIntelligenceAvailability
    private(set) var suggestCallCount = 0
    private(set) var lastPantryItems: [PantryItem] = []

    init(
        result: Result<[RawRecipeSuggestion], Error> = .success([]),
        availability: AppleIntelligenceAvailability = .available
    ) {
        self.result = result
        self.availability = availability
    }

    func suggestRecipes(from pantryItems: [PantryItem]) async throws -> [RawRecipeSuggestion] {
        suggestCallCount += 1
        lastPantryItems = pantryItems
        return try result.get()
    }
}
