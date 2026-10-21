//
//  FindOnlineRecipesFromPantryUseCaseTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
private final class FailingPantryRepository: PantryRepository {
    struct Failure: Error {}
    func fetchAll() async throws -> [PantryItem] { throw Failure() }
    func fetch(id: UUID) async throws -> PantryItem? { throw Failure() }
    func fetchExpiring(before date: Date) async throws -> [PantryItem] { throw Failure() }
    func add(_ item: PantryItem) async throws {}
    func update(_ item: PantryItem) async throws {}
    func remove(id: UUID) async throws {}
}

@MainActor
final class FindOnlineRecipesFromPantryUseCaseTests: XCTestCase {
    func test_happyPath_searchesWithPantryNames_andSortsByFewestMissing() async throws {
        let service = MockOnlineRecipeService(result: .success([
            OnlineRecipeFixtures.match(id: 1, missedCount: 3),
            OnlineRecipeFixtures.match(id: 2, missedCount: 0),
            OnlineRecipeFixtures.match(id: 3, missedCount: 1),
        ]))
        let useCase = FindOnlineRecipesFromPantryUseCase(
            recipeService: service,
            pantryRepository: OnlineRecipeFixtures.pantry("Garlic", "Chicken")
        )

        let result = try await useCase.execute(preferences: .default)

        XCTAssertEqual(result.matches.map(\.id), [2, 3, 1])
        XCTAssertEqual(result.excludedForSafetyCount, 0)
        XCTAssertEqual(service.receivedCriteria.first?.pantryIngredientNames, ["Garlic", "Chicken"])
    }

    func test_duplicatePantryNames_areSentOnce() async throws {
        let service = MockOnlineRecipeService(result: .success([OnlineRecipeFixtures.match()]))
        let useCase = FindOnlineRecipesFromPantryUseCase(
            recipeService: service,
            pantryRepository: OnlineRecipeFixtures.pantry("Milk", "milk ", "Eggs")
        )

        _ = try await useCase.execute(preferences: .default)

        XCTAssertEqual(service.receivedCriteria.first?.pantryIngredientNames, ["Milk", "Eggs"])
    }

    func test_emptyPantry_throwsEmptyPantry_withoutCallingService() async {
        let service = MockOnlineRecipeService(result: .success([]))
        let useCase = FindOnlineRecipesFromPantryUseCase(recipeService: service, pantryRepository: InMemoryPantryRepository())

        await assertThrows(.emptyPantry) { try await useCase.execute(preferences: .default) }
        XCTAssertTrue(service.receivedCriteria.isEmpty)
    }

    func test_pantryLoadFailure_throwsPantryUnavailable() async {
        let useCase = FindOnlineRecipesFromPantryUseCase(
            recipeService: MockOnlineRecipeService(result: .success([])),
            pantryRepository: FailingPantryRepository()
        )
        await assertThrows(.pantryUnavailable) { try await useCase.execute(preferences: .default) }
    }

    func test_serviceError_isPropagated() async {
        let useCase = FindOnlineRecipesFromPantryUseCase(
            recipeService: MockOnlineRecipeService(result: .failure(.quotaExceeded)),
            pantryRepository: OnlineRecipeFixtures.pantry("Rice")
        )
        await assertThrows(.quotaExceeded) { try await useCase.execute(preferences: .default) }
    }

    func test_safetyFilter_dropsContainingAndUnverifiedRecipes() async throws {
        // `.egg` is composition-grade, so it survives sanitising and is
        // actually enforced. Recipe 1 contains it; recipe 2 could not be
        // screened at all, which fails closed; recipe 3 is clear of it.
        let service = MockOnlineRecipeService(result: .success([
            OnlineRecipeFixtures.match(id: 1, intolerances: [.egg]),
            OnlineRecipeFixtures.match(id: 2, intolerances: nil),
            OnlineRecipeFixtures.match(id: 3, intolerances: [.dairy]),
        ]))
        let useCase = FindOnlineRecipesFromPantryUseCase(recipeService: service, pantryRepository: OnlineRecipeFixtures.pantry("Rice"))

        let result = try await useCase.execute(preferences: OnlineRecipePreferences(intolerances: [.egg]))

        XCTAssertEqual(result.matches.map(\.id), [3])
        XCTAssertEqual(result.excludedForSafetyCount, 2)
    }

    func test_unassessableIntolerance_isNotTreatedAsAFilter() async throws {
        // Gluten is `.productProvenance`. Selecting it must not silently
        // behave like a coeliac-safe filter: it is sanitised out, so the
        // unverified recipe is kept rather than being hidden under a claim
        // the app never checked. The Filters screen is what tells the user
        // gluten is not matched - see OnlineRecipePreferencesView.
        let service = MockOnlineRecipeService(result: .success([
            OnlineRecipeFixtures.match(id: 1, intolerances: nil),
            OnlineRecipeFixtures.match(id: 2, intolerances: [.gluten]),
        ]))
        let useCase = FindOnlineRecipesFromPantryUseCase(recipeService: service, pantryRepository: OnlineRecipeFixtures.pantry("Rice"))

        let result = try await useCase.execute(preferences: OnlineRecipePreferences(intolerances: [.gluten]))

        XCTAssertEqual(result.matches.count, 2)
        XCTAssertEqual(result.excludedForSafetyCount, 0)
        XCTAssertEqual(
            service.receivedCriteria.last?.preferences.intolerances,
            [],
            "An intolerance FridgeFit cannot assess must not be sent as though it were being checked"
        )
    }

    func test_noIntolerances_keepsUnverifiedRecipes() async throws {
        let service = MockOnlineRecipeService(result: .success([OnlineRecipeFixtures.match(id: 2, intolerances: nil)]))
        let useCase = FindOnlineRecipesFromPantryUseCase(recipeService: service, pantryRepository: OnlineRecipeFixtures.pantry("Rice"))

        let result = try await useCase.execute(preferences: .default)

        XCTAssertEqual(result.matches.map(\.id), [2])
    }

    func test_everythingFilteredOut_throwsNoResults() async {
        let service = MockOnlineRecipeService(result: .success([OnlineRecipeFixtures.match(intolerances: [.egg])]))
        let useCase = FindOnlineRecipesFromPantryUseCase(recipeService: service, pantryRepository: OnlineRecipeFixtures.pantry("Eggs"))

        await assertThrows(.noResults) { try await useCase.execute(preferences: OnlineRecipePreferences(intolerances: [.egg])) }
    }

    func test_errorMessages_areHumanReadable() {
        let all: [OnlineRecipeSearchError] = [.notConfigured, .emptyPantry, .pantryUnavailable, .unauthorized, .quotaExceeded, .providerUnavailable, .network, .timeout, .malformedResponse, .noResults]
        for error in all {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error) needs a message")
        }
    }

    private func assertThrows(
        _ expected: OnlineRecipeSearchError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> OnlineRecipeSearchResult
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? OnlineRecipeSearchError, expected, file: file, line: line)
        }
    }
}
