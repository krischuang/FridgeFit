//
//  OnlineRecipe.swift
//  FridgeFit
//

import Foundation

/// A recipe fetched from an online recipe provider (Spoonacular).
///
/// Deliberately a separate type from `Recipe`: bundled recipes carry
/// essential/optional roles and exact units that the deterministic
/// feasibility engine relies on, while online data is looser (free-text
/// units, no roles, sometimes no instructions). Keeping them apart means
/// nothing fetched from the network can leak into - or weaken - the
/// existing Recipes feature.
nonisolated struct OnlineRecipe: Identifiable, Hashable, Codable {
    /// The provider's own recipe id, stable across searches.
    let id: Int
    var title: String
    var imageURL: URL?
    /// `nil` when the provider doesn't report a prep time.
    var readyInMinutes: Int?
    var servings: Int?
    /// Plain-text summary (the provider's HTML tags are stripped).
    var summary: String?
    var sourceName: String?
    var sourceURL: URL?
    var healthScore: Double?
    /// Provider diet labels, e.g. "vegan", "gluten free".
    var diets: [String]
    var ingredients: [OnlineRecipeIngredient]
    /// One entry per step, in cooking order. Empty when the provider has no
    /// structured method - the detail screen then links to `sourceURL`.
    var steps: [String]
    /// Intolerances this recipe was found to contain.
    ///
    /// `nil` means **unverified** (no ingredient data to analyse), which the
    /// safety filter treats as unsafe for anyone with an intolerance set -
    /// see `FindOnlineRecipesFromPantryUseCase`.
    var containsIntolerances: Set<FoodIntolerance>?
}

/// One ingredient line of an `OnlineRecipe`, as the provider reported it.
nonisolated struct OnlineRecipeIngredient: Identifiable, Hashable, Codable {
    let id: UUID
    /// The provider's ingredient id - more reliable than the name for
    /// matching "garlic" and "garlic clove" as the same thing.
    var providerID: Int?
    var name: String
    var amount: Double
    /// `nil` when the provider's unit doesn't map onto `MeasurementUnit`
    /// (e.g. "pinch", "can"); `originalUnit` keeps the raw text for display.
    var unit: MeasurementUnit?
    var originalUnit: String
    /// `true` when the amount can't be trusted as a real quantity - e.g. the
    /// provider reported the unit as "servings", which is not a piece count.
    var quantityIsUncertain: Bool

    init(
        id: UUID = UUID(),
        providerID: Int?,
        name: String,
        amount: Double,
        unit: MeasurementUnit?,
        originalUnit: String,
        quantityIsUncertain: Bool = false
    ) {
        self.id = id
        self.providerID = providerID
        self.name = name
        self.amount = amount
        self.unit = unit
        self.originalUnit = originalUnit
        self.quantityIsUncertain = quantityIsUncertain
    }

    /// Display text such as "200 g", "1 pinch", or "Amount unclear".
    var formattedQuantity: String {
        if quantityIsUncertain { return "Amount unclear" }
        if let unit { return unit.formatted(amount) }
        let isWhole = amount.truncatingRemainder(dividingBy: 1) == 0
        let value = isWhole ? String(format: "%.0f", amount) : String(format: "%.1f", amount)
        let trimmedUnit = originalUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedUnit.isEmpty ? value : "\(value) \(trimmedUnit)"
    }

    /// Whether this line refers to the same ingredient as `other`: provider
    /// id first, normalised name as a fallback.
    func isSameIngredient(as other: OnlineRecipeIngredient) -> Bool {
        if let providerID, let otherID = other.providerID {
            return providerID == otherID
        }
        return Self.normalized(name) == Self.normalized(other.name)
    }

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// A search hit: the recipe plus how it lines up with the user's pantry.
///
/// The provider decides which pantry ingredients a recipe uses and which
/// further ones it needs; this app doesn't re-derive that match.
nonisolated struct OnlineRecipeMatch: Identifiable, Hashable, Codable {
    var recipe: OnlineRecipe
    /// Pantry ingredient names this recipe uses.
    var usedIngredientNames: [String]
    /// Ingredients the recipe needs that the pantry doesn't have.
    var missedIngredients: [OnlineRecipeIngredient]
    /// `true` when served from the offline cache - the UI says so, so
    /// possibly-stale data is never presented as fresh.
    var isFromCache: Bool = false

    var id: Int { recipe.id }

    /// Whether `ingredient` is one the user still needs to buy.
    func isMissing(_ ingredient: OnlineRecipeIngredient) -> Bool {
        missedIngredients.contains { $0.isSameIngredient(as: ingredient) }
    }
}
