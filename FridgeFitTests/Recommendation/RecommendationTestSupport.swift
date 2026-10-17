//
//  RecommendationTestSupport.swift
//  FridgeFitTests
//

import Foundation
@testable import FridgeFit

/// Fixtures shared by the recommendation test suites.
///
/// Everything is built from main's own types and test doubles -
/// `InMemoryPantryRepository` and `InMemoryRecipeRepository` - so the
/// tests exercise the same abstractions the app runs on.
enum RecommendationFixture {

    /// A fixed "now" so expiry boundaries are assertable. Midday avoids
    /// any ambiguity about which day a start-of-day calculation lands on.
    static let now = Calendar.current.date(
        from: DateComponents(year: 2026, month: 6, day: 15, hour: 12)
    )!

    static func date(daysFromNow days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: now)!
    }

    // MARK: - Recipes

    /// A recipe with full metadata. Two essential ingredients unless
    /// overridden, so "one short" and "two short" cases are easy to set up.
    static func recipe(
        id: UUID = UUID(),
        title: String,
        cuisine: Cuisine? = .italian,
        tastes: Set<TastePreference>? = [.savoury],
        dietaryLabels: Set<DietaryRestriction>? = [],
        minutes: Int? = 30,
        difficulty: CookingDifficulty? = .easy,
        ingredients: [RecipeIngredient]? = nil
    ) -> Recipe {
        Recipe(
            id: id,
            title: title,
            summary: "Fixture.",
            ingredients: ingredients ?? [
                essential("Pasta", 200, .grams),
                essential("Tomato", 300, .grams),
            ],
            instructions: ["Cook it."],
            symbolName: "fork.knife",
            cuisine: cuisine,
            tastePreferences: tastes,
            dietaryLabels: dietaryLabels,
            totalCookingTimeInMinutes: minutes,
            difficulty: difficulty
        )
    }

    /// A recipe as it would decode from data written before the
    /// recommendation metadata existed: every new field `nil`.
    static func legacyRecipe(
        id: UUID = UUID(),
        title: String = "Legacy Recipe",
        ingredients: [RecipeIngredient]? = nil
    ) -> Recipe {
        Recipe(
            id: id,
            title: title,
            summary: "Fixture.",
            ingredients: ingredients ?? [essential("Pasta", 200, .grams)],
            instructions: ["Cook it."]
        )
    }

    static func essential(
        _ name: String,
        _ quantity: Double,
        _ unit: MeasurementUnit
    ) -> RecipeIngredient {
        RecipeIngredient(
            ingredient: Ingredient(name: name),
            quantity: quantity,
            unit: unit,
            role: .essential
        )
    }

    static func optional(
        _ name: String,
        _ quantity: Double,
        _ unit: MeasurementUnit
    ) -> RecipeIngredient {
        RecipeIngredient(
            ingredient: Ingredient(name: name),
            quantity: quantity,
            unit: unit,
            role: .optional
        )
    }

    // MARK: - Pantry

    static func pantryItem(
        _ name: String,
        _ quantity: Double,
        _ unit: MeasurementUnit,
        expiresInDays days: Int? = nil
    ) -> PantryItem {
        PantryItem(
            ingredient: Ingredient(name: name),
            quantity: quantity,
            unit: unit,
            expiryDate: days.map { date(daysFromNow: $0) }
        )
    }

    /// A pantry item whose expiry is relative to the *real* clock.
    ///
    /// For callers that go through `RecommendationViewModel`, which takes
    /// no injected `now` and so measures expiry from `Date.now`. Use
    /// `pantryItem(_:_:_:expiresInDays:)` instead wherever the use case
    /// can be called directly with the fixed `now` - that is the
    /// deterministic path and is what the rule tests use.
    static func pantryItemExpiringFromToday(
        _ name: String,
        _ quantity: Double,
        _ unit: MeasurementUnit,
        inDays days: Int
    ) -> PantryItem {
        PantryItem(
            ingredient: Ingredient(name: name),
            quantity: quantity,
            unit: unit,
            expiryDate: Calendar.current.date(byAdding: .day, value: days, to: .now)
        )
    }

    /// A pantry holding more than enough of both default recipe
    /// ingredients, with no expiry dates recorded.
    static var stockedPantry: [PantryItem] {
        [
            pantryItem("Pasta", 500, .grams),
            pantryItem("Tomato", 1, .kilograms),
        ]
    }

    // MARK: - Assembly

    static func useCase(
        recipes: [Recipe],
        pantry: [PantryItem]
    ) -> GenerateContextAwareRecommendationsUseCase {
        GenerateContextAwareRecommendationsUseCase(
            recipeRepository: InMemoryRecipeRepository(recipes: recipes),
            pantryRepository: InMemoryPantryRepository(seedItems: pantry)
        )
    }

    /// Runs the full pipeline the way the app does, at the fixed `now`.
    static func recommendations(
        recipes: [Recipe],
        pantry: [PantryItem],
        context: CookingContext = .unrestricted,
        session: RecommendationSession? = nil
    ) async throws -> [RecipeRecommendation] {
        try await useCase(recipes: recipes, pantry: pantry)
            .execute(context: context, session: session, now: now)
    }

    /// Evaluates one recipe through main's feasibility engine and then the
    /// suitability rules, exactly as the generator does.
    static func suitability(
        of recipe: Recipe,
        pantry: [PantryItem],
        context: CookingContext = .unrestricted
    ) -> RecipeSuitabilityOutcome {
        let feasibility = EvaluateRecipeFeasibilityUseCase.evaluate(recipe: recipe, against: pantry)
        return EvaluateRecipeSuitabilityUseCase().execute(
            recipe: recipe,
            feasibility: feasibility,
            pantryItems: pantry,
            context: context,
            now: now
        )
    }
}

/// A repository that always fails, for the unavailable-data paths.
final class UnavailablePantryRepository: PantryRepository {
    struct Failure: Error {}

    func fetchAll() async throws -> [PantryItem] { throw Failure() }
    func fetch(id: UUID) async throws -> PantryItem? { throw Failure() }
    func fetchExpiring(before date: Date) async throws -> [PantryItem] { throw Failure() }
    func add(_ item: PantryItem) async throws { throw Failure() }
    func update(_ item: PantryItem) async throws { throw Failure() }
    func remove(id: UUID) async throws { throw Failure() }
}

final class UnavailableRecipeRepository: RecipeRepository {
    struct Failure: Error {}

    func fetchAll() async throws -> [Recipe] { throw Failure() }
}

extension RecipeSuitabilityOutcome {
    /// The suitability, or `nil` if the recipe was excluded.
    var suitable: RecipeSuitability? {
        if case .suitable(let suitability) = self { return suitability }
        return nil
    }

    /// The exclusion reason, or `nil` if the recipe was suitable.
    var exclusion: RecipeExclusionReason? {
        if case .excluded(let reason) = self { return reason }
        return nil
    }
}
