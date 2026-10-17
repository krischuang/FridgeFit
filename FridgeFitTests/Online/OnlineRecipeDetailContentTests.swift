//
//  OnlineRecipeDetailContentTests.swift
//  FridgeFitTests
//

import SwiftUI
import XCTest
@testable import FridgeFit

@MainActor
final class OnlineRecipeDetailContentTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        return calendar
    }()
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))!

    private func line(_ name: String, _ amount: Double, _ unit: MeasurementUnit?, id: Int? = nil) -> OnlineRecipeIngredient {
        OnlineRecipeIngredient(providerID: id, name: name, amount: amount, unit: unit, originalUnit: unit?.symbol ?? "")
    }

    private func match() -> OnlineRecipeMatch {
        var recipe = OnlineRecipeFixtures.recipe(id: 10, title: "Spinach & Mushroom Rice Bowl")
        recipe.ingredients = [
            line("fresh spinach", 150, .grams, id: 1),
            line("button mushrooms", 200, .grams, id: 2),
            line("eggs", 2, .pieces, id: 3),
            line("spring onion", 1, .pieces, id: 4),
        ]
        return OnlineRecipeMatch(
            recipe: recipe,
            usedIngredientNames: ["fresh spinach", "button mushrooms", "eggs"],
            missedIngredients: [line("spring onion", 1, .pieces, id: 4)]
        )
    }

    private func pantryItem(_ name: String, days: Int?, location: StorageLocation?) -> PantryItem {
        PantryItem(
            ingredient: Ingredient(name: name),
            quantity: 1,
            unit: .pieces,
            expiryDate: days.flatMap { calendar.date(byAdding: .day, value: $0, to: now) },
            storageLocation: location
        )
    }

    // MARK: - Breakdown

    func test_build_splitsHaveAndMissing_withReadiness() {
        let content = OnlineRecipeDetailContent.build(match: match(), pantry: [], now: now, calendar: calendar)

        XCTAssertEqual(content.have.map(\.name), ["Fresh Spinach", "Button Mushrooms", "Eggs"])
        XCTAssertEqual(content.missing.map(\.name), ["Spring Onion"])
        XCTAssertEqual(content.readyCount, 3)
        XCTAssertEqual(content.totalCount, 4)
        XCTAssertEqual(content.matchPercent, 75)
        XCTAssertEqual(content.missing.first?.status, .missing)
    }

    func test_build_usesPantryForLocationAndFreshness() {
        let pantry = [
            pantryItem("Fresh Spinach", days: 1, location: .fridge),
            pantryItem("Button Mushroom", days: 3, location: .fridge),
            pantryItem("Egg", days: 20, location: nil),
        ]

        let have = OnlineRecipeDetailContent.build(match: match(), pantry: pantry, now: now, calendar: calendar).have

        XCTAssertEqual(have.map(\.status), [.expiresTomorrow, .daysLeft(3), .fresh])
        XCTAssertEqual(have.map(\.location), [.fridge, .fridge, .pantry])
        XCTAssertEqual(have.first?.quantity, "150 g")
    }

    func test_build_unmatchedPantryName_isInStockWithoutLocation() {
        let have = OnlineRecipeDetailContent.build(
            match: match(),
            pantry: [pantryItem("Spinach", days: 1, location: .fridge)],
            now: now,
            calendar: calendar
        ).have

        XCTAssertEqual(have.first?.status, .inStock, "'fresh spinach' must not be guessed onto 'Spinach'")
        XCTAssertNil(have.first?.location)
    }

    func test_build_withoutIngredientList_fallsBackToProviderNames() {
        var bare = match()
        bare.recipe.ingredients = []

        let content = OnlineRecipeDetailContent.build(match: bare, pantry: [], now: now, calendar: calendar)

        XCTAssertEqual(content.readyCount, 3)
        XCTAssertEqual(content.missing.map(\.name), ["Spring Onion"])
    }

    func test_statusTitles_readNaturally() {
        XCTAssertEqual(OnlineRecipeDetailContent.StockStatus.expiresTomorrow.title, "Expires tomorrow")
        XCTAssertEqual(OnlineRecipeDetailContent.StockStatus.daysLeft(3).title, "3 days left")
        XCTAssertEqual(OnlineRecipeDetailContent.StockStatus.missing.title, "Missing")
    }

    // MARK: - FridgeFix target

    func test_fridgeFixTarget_isTheMissingEssentialIngredient() throws {
        let target = try XCTUnwrap(OnlineRecipeFridgeFixTarget.make(for: match(), readyCount: 3, totalCount: 4))

        XCTAssertEqual(target.ingredient.ingredient.name, "Spring Onion")
        XCTAssertEqual(target.feasibility.status, .almostMakeable)
        XCTAssertTrue(target.recipe.ingredients.contains { $0.id == target.ingredient.id })
    }

    func test_fridgeFixTarget_nilWhenNothingIsMissing() {
        var complete = match()
        complete.missedIngredients = []
        XCTAssertNil(OnlineRecipeFridgeFixTarget.make(for: complete, readyCount: 4, totalCount: 4))
    }

    // MARK: - Cooking

    func test_shortLabel_takesFirstWords() {
        XCTAssertEqual(OnlineRecipeCookingView.shortLabel(for: "Wash and chop the spinach and mushrooms."), "Wash and chop the…")
        XCTAssertEqual(OnlineRecipeCookingView.shortLabel(for: "Boil rice."), "Boil rice")
    }

    // MARK: - Rendering

    private func assertRenders(_ view: some View, file: StaticString = #filePath, line: UInt = #line) {
        let renderer = ImageRenderer(content: view.frame(width: 390, height: 1600))
        renderer.scale = 1
        XCTAssertNotNil(renderer.uiImage, file: file, line: line)
    }

    func test_detailRenders_withExpiryPantryAndFridgeFix() {
        let pantry = InMemoryPantryRepository()
        assertRenders(
            NavigationStack {
                OnlineRecipeDetailView(
                    match: match(),
                    intolerances: [],
                    recipeViewModel: RecipeViewModel(pantryRepository: pantry, savedRecipeRepository: InMemorySavedRecipeRepository()),
                    expiryUse: OnlineRecipeExpiryUse(urgent: [UrgentIngredientUse(ingredientName: "Fresh Spinach", urgency: .tomorrow, daysUntilExpiry: 1)]),
                    onHide: {},
                    pantrySnapshot: [pantryItem("Fresh Spinach", days: 1, location: .fridge)],
                    substitutionViewModel: SubstitutionViewModel(
                        useCase: GetIngredientSubstitutionsUseCase(
                            substitutionService: MockSubstitutionService(),
                            pantryRepository: pantry,
                            cache: SubstitutionCache()
                        )
                    )
                )
            }
        )
    }

    func test_detailRenders_withExpiredIngredientAndNoSteps() {
        var noSteps = match()
        noSteps.recipe.steps = []
        assertRenders(
            NavigationStack {
                OnlineRecipeDetailView(
                    match: noSteps,
                    intolerances: [.dairy],
                    recipeViewModel: RecipeViewModel(pantryRepository: InMemoryPantryRepository()),
                    expiryUse: OnlineRecipeExpiryUse(expired: ["Eggs"])
                )
            }
        )
    }

    func test_cookingViewRenders() {
        assertRenders(OnlineRecipeCookingView(title: "Bowl", steps: ["Cook rice.", "Serve."]))
    }
}
