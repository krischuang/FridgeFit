//
//  OnlineRecipeExpiryRankingTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class OnlineRecipeExpiryRankingTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        return calendar
    }()
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))!

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now)!
    }

    private func item(_ name: String, expiresIn days: Int?) -> PantryItem {
        PantryItem(ingredient: Ingredient(name: name), quantity: 1, unit: .pieces, expiryDate: days.map(day))
    }

    // MARK: - Name matching

    func test_namesMatch_foldsCaseWhitespaceAndPlurals() {
        XCTAssertTrue(OnlineRecipeExpiryRanking.namesMatch("tomatoes", "Tomato"))
        XCTAssertTrue(OnlineRecipeExpiryRanking.namesMatch(" Eggs ", "egg"))
        XCTAssertTrue(OnlineRecipeExpiryRanking.namesMatch("berries", "Berry"))
        XCTAssertTrue(OnlineRecipeExpiryRanking.namesMatch("chicken breasts", "Chicken Breast"))
        XCTAssertTrue(OnlineRecipeExpiryRanking.namesMatch("spinach (fresh)", "Spinach"))
    }

    func test_namesMatch_neverSubstringMatches() {
        XCTAssertFalse(OnlineRecipeExpiryRanking.namesMatch("coconut milk", "Milk"))
        XCTAssertFalse(OnlineRecipeExpiryRanking.namesMatch("green onion", "Onion"))
        XCTAssertFalse(OnlineRecipeExpiryRanking.namesMatch("", ""))
    }

    // MARK: - Urgent pantry items

    func test_urgentPantryItems_usesExpiryServiceWindow_mostUrgentFirst() {
        let pantry = [
            item("Rice", expiresIn: nil),
            item("Yoghurt", expiresIn: 3),
            item("Milk", expiresIn: 1),
            item("Cheese", expiresIn: 6),   // this week: not prioritised
            item("Ham", expiresIn: -1),     // expired: never "use first"
            item("Spinach", expiresIn: 0),
        ]

        let urgent = OnlineRecipeExpiryRanking.urgentPantryItems(in: pantry, now: now, calendar: calendar)

        XCTAssertEqual(urgent.map(\.ingredientName), ["Spinach", "Milk", "Yoghurt"])
        XCTAssertEqual(urgent.map(\.urgency), [.today, .tomorrow, .soon])
    }

    func test_requestOrder_putsUrgentNamesFirst_keepingTheRest() {
        let urgent = [UrgentIngredientUse(ingredientName: "Milk", urgency: .tomorrow, daysUntilExpiry: 1)]

        let ordered = OnlineRecipeExpiryRanking.requestOrder(names: ["Rice", "Garlic", "Milk", "Eggs"], urgent: urgent)

        XCTAssertEqual(ordered, ["Milk", "Rice", "Garlic", "Eggs"])
    }

    // MARK: - Per-recipe use

    func test_expiryUse_splitsUrgentAndExpired_andCreditsEachItemOnce() {
        let pantry = [item("Milk", expiresIn: 1), item("Ham", expiresIn: -2), item("Rice", expiresIn: 30)]
        let match = OnlineRecipeFixtures.match(used: ["milk", "Milk", "ham", "rice"])

        let use = OnlineRecipeExpiryRanking.expiryUse(of: match, pantry: pantry, now: now, calendar: calendar)

        XCTAssertEqual(use.urgent.map(\.ingredientName), ["Milk"])
        XCTAssertEqual(use.expired, ["Ham"])
    }

    func test_expiryUse_noDatesOrNoMatches_isNone() {
        let use = OnlineRecipeExpiryRanking.expiryUse(
            of: OnlineRecipeFixtures.match(used: ["coconut milk"]),
            pantry: [item("Milk", expiresIn: 0), item("Rice", expiresIn: nil)],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(use, .none)
    }

    // MARK: - Ranking

    func test_ranked_urgencyBeatsMissingCount_andExpiredSinks() {
        let plain = OnlineRecipeFixtures.match(id: 1, missedCount: 0)
        let soon = OnlineRecipeFixtures.match(id: 2, missedCount: 3)
        let today = OnlineRecipeFixtures.match(id: 3, missedCount: 4)
        let expired = OnlineRecipeFixtures.match(id: 4, missedCount: 0)
        let uses: [Int: OnlineRecipeExpiryUse] = [
            2: OnlineRecipeExpiryUse(urgent: [UrgentIngredientUse(ingredientName: "Yoghurt", urgency: .soon, daysUntilExpiry: 3)]),
            3: OnlineRecipeExpiryUse(urgent: [UrgentIngredientUse(ingredientName: "Spinach", urgency: .today, daysUntilExpiry: 0)]),
            4: OnlineRecipeExpiryUse(
                urgent: [UrgentIngredientUse(ingredientName: "Spinach", urgency: .today, daysUntilExpiry: 0)],
                expired: ["Ham"]
            ),
        ]

        let ranked = OnlineRecipeExpiryRanking.ranked([plain, soon, today, expired], expiryUse: uses)

        XCTAssertEqual(ranked.map(\.id), [3, 2, 1, 4])
    }

    func test_ranked_moreUrgentItemsWin_atEqualUrgency() {
        let one = OnlineRecipeFixtures.match(id: 1)
        let two = OnlineRecipeFixtures.match(id: 2)
        let milk = UrgentIngredientUse(ingredientName: "Milk", urgency: .tomorrow, daysUntilExpiry: 1)
        let eggs = UrgentIngredientUse(ingredientName: "Eggs", urgency: .soon, daysUntilExpiry: 2)

        let ranked = OnlineRecipeExpiryRanking.ranked(
            [one, two],
            expiryUse: [1: OnlineRecipeExpiryUse(urgent: [milk]), 2: OnlineRecipeExpiryUse(urgent: [milk, eggs])]
        )

        XCTAssertEqual(ranked.map(\.id), [2, 1])
    }

    func test_ranked_withoutExpiryData_keepsFewestMissingOrder() {
        let ranked = OnlineRecipeExpiryRanking.ranked(
            [OnlineRecipeFixtures.match(id: 1, missedCount: 2), OnlineRecipeFixtures.match(id: 2, missedCount: 0)],
            expiryUse: [:]
        )
        XCTAssertEqual(ranked.map(\.id), [2, 1])
    }

    // MARK: - Through the use case

    func test_useCase_ranksExpiringFirst_sendsThemFirst_andReportsThem() async throws {
        let pantry = InMemoryPantryRepository(seedItems: [
            item("Rice", expiresIn: nil),
            item("Spinach", expiresIn: 1),
        ])
        let service = MockOnlineRecipeService(result: .success([
            OnlineRecipeFixtures.match(id: 1, used: ["rice"], missedCount: 0),
            OnlineRecipeFixtures.match(id: 2, used: ["spinach"], missedCount: 2),
        ]))
        let fixedNow = now
        let useCase = FindOnlineRecipesFromPantryUseCase(
            recipeService: service,
            pantryRepository: pantry,
            now: { fixedNow },
            calendar: calendar
        )

        let result = try await useCase.execute(preferences: .default)

        XCTAssertEqual(result.matches.map(\.id), [2, 1])
        XCTAssertEqual(service.receivedCriteria.first?.pantryIngredientNames, ["Spinach", "Rice"])
        XCTAssertEqual(result.urgentPantryIngredients.map(\.ingredientName), ["Spinach"])
        XCTAssertEqual(result.expiryUse[2]?.urgent.first?.urgency, .tomorrow)
        XCTAssertNil(result.expiryUse[1])
    }

    func test_viewModel_publishesExpiryUse_andClearsItOnFilterChange() async {
        let pantry = InMemoryPantryRepository(seedItems: [item("Spinach", expiresIn: 0)])
        let fixedNow = now
        let viewModel = OnlineRecipeSearchViewModel(
            useCase: FindOnlineRecipesFromPantryUseCase(
                recipeService: MockOnlineRecipeService(result: .success([OnlineRecipeFixtures.match(id: 9, used: ["spinach"])])),
                pantryRepository: pantry,
                now: { fixedNow },
                calendar: calendar
            ),
            preferencesStore: InMemoryOnlineRecipePreferencesStore()
        )

        await viewModel.search()
        XCTAssertTrue(viewModel.expiryUse(for: viewModel.matches[0]).usesUrgentIngredient)
        XCTAssertEqual(viewModel.urgentPantryIngredients.map(\.ingredientName), ["Spinach"])

        viewModel.updatePreferences(OnlineRecipePreferences(diet: .vegetarian))
        XCTAssertTrue(viewModel.expiryUseByRecipeID.isEmpty)
        XCTAssertTrue(viewModel.urgentPantryIngredients.isEmpty)
    }
}
