//
//  OnlineRecipeDetailContent.swift
//  FridgeFit
//

import Foundation

/// What the Discover detail screen shows about a recipe's ingredients:
/// what the user already has (and where, and how fresh), and what they
/// still need.
///
/// Rules:
/// - "Have" vs "need" is the recipe service's verdict
///   (`OnlineRecipeMatch.isMissing`), the same one the Discover list shows,
///   so the two screens never disagree.
/// - Location and freshness come from the user's pantry, matched with the
///   same conservative rule as the expiry ranking
///   (`OnlineRecipeExpiryRanking.namesMatch`). When no pantry item matches,
///   the row says "In stock" with no location rather than guessing one.
/// - Freshness wording comes from `ExpiryService`.
/// - The readiness figure is a count of ingredient lines, not quantities.
nonisolated struct OnlineRecipeDetailContent: Equatable {
    enum StockStatus: Equatable {
        case expired
        case expiresToday
        case expiresTomorrow
        case daysLeft(Int)
        case fresh
        case inStock
        case missing

        var title: String {
            switch self {
            case .expired: return "Expired"
            case .expiresToday: return "Expires today"
            case .expiresTomorrow: return "Expires tomorrow"
            case .daysLeft(let days): return "\(days) days left"
            case .fresh: return "Fresh"
            case .inStock: return "In stock"
            case .missing: return "Missing"
            }
        }
    }

    struct Line: Identifiable, Equatable {
        let id: UUID
        let name: String
        /// e.g. "150 g"; empty when the provider gave no usable amount.
        let quantity: String
        let quantityIsUncertain: Bool
        /// Where the matching pantry item is kept; `nil` when unknown.
        let location: StorageLocation?
        let status: StockStatus
    }

    var have: [Line]
    var missing: [Line]

    var readyCount: Int { have.count }
    var totalCount: Int { have.count + missing.count }
    var matchPercent: Int {
        guard totalCount > 0 else { return 0 }
        return Int((Double(readyCount) / Double(totalCount) * 100).rounded())
    }

    static func build(
        match: OnlineRecipeMatch,
        pantry: [PantryItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> OnlineRecipeDetailContent {
        var have: [Line] = []
        var missing: [Line] = []

        let ingredients = match.recipe.ingredients
        if ingredients.isEmpty {
            // No full ingredient list: fall back to the provider's used/missed names.
            have = match.usedIngredientNames.map { name in
                line(id: UUID(), name: name, quantity: "", uncertain: false, pantry: pantry, now: now, calendar: calendar)
            }
            missing = match.missedIngredients.map(missingLine)
            return OnlineRecipeDetailContent(have: have, missing: missing)
        }

        for ingredient in ingredients {
            if match.isMissing(ingredient) {
                missing.append(missingLine(ingredient))
            } else {
                have.append(line(
                    id: ingredient.id,
                    name: ingredient.name,
                    quantity: quantityText(ingredient),
                    uncertain: ingredient.quantityIsUncertain,
                    pantry: pantry,
                    now: now,
                    calendar: calendar
                ))
            }
        }
        return OnlineRecipeDetailContent(have: have, missing: missing)
    }

    static func quantityText(_ ingredient: OnlineRecipeIngredient) -> String {
        if !ingredient.quantityIsUncertain && ingredient.amount <= 0 { return "" }
        return ingredient.formattedQuantity
    }

    private static func missingLine(_ ingredient: OnlineRecipeIngredient) -> Line {
        Line(
            id: ingredient.id,
            name: OnlineIngredientName.displayName(ingredient.name),
            quantity: quantityText(ingredient),
            quantityIsUncertain: ingredient.quantityIsUncertain,
            location: nil,
            status: .missing
        )
    }

    private static func line(
        id: UUID,
        name: String,
        quantity: String,
        uncertain: Bool,
        pantry: [PantryItem],
        now: Date,
        calendar: Calendar
    ) -> Line {
        let item = pantry.first { OnlineRecipeExpiryRanking.namesMatch(name, $0.name) }
        return Line(
            id: id,
            name: OnlineIngredientName.displayName(name),
            quantity: quantity,
            quantityIsUncertain: uncertain,
            location: item?.storage,
            status: status(for: item, now: now, calendar: calendar)
        )
    }

    static func status(for item: PantryItem?, now: Date, calendar: Calendar) -> StockStatus {
        guard let item, let state = ExpiryService.state(for: item.expiryDate, now: now, calendar: calendar) else {
            return .inStock
        }
        switch state.urgency {
        case .expired: return .expired
        case .today: return .expiresToday
        case .tomorrow: return .expiresTomorrow
        case .soon, .thisWeek: return .daysLeft(state.daysUntilExpiry ?? 0)
        case .none: return .fresh
        }
    }
}

/// The missing ingredient FridgeFix (the substitution assistant) is asked
/// about, plus the `Recipe` form the substitution pipeline needs.
///
/// The online recipe is converted with `SaveOnlineRecipeUseCase.recipe(from:)`
/// - the same conversion saving uses - and the target is the first
/// *essential* ingredient the recipe service reported missing. Conversion
/// creates fresh ingredient ids, so the caller must build this once per
/// screen and keep it; `SubstitutionViewModel` keys its state by those ids.
struct OnlineRecipeFridgeFixTarget {
    let recipe: Recipe
    let ingredient: RecipeIngredient
    let feasibility: RecipeFeasibilityResult

    static func make(for match: OnlineRecipeMatch, readyCount: Int, totalCount: Int) -> OnlineRecipeFridgeFixTarget? {
        guard !match.missedIngredients.isEmpty,
              let recipe = try? SaveOnlineRecipeUseCase.recipe(from: match.recipe)
        else { return nil }

        let missedNames = match.missedIngredients.map(\.name)
        let candidates = recipe.ingredients.filter { ingredient in
            missedNames.contains { OnlineRecipeExpiryRanking.namesMatch($0, ingredient.ingredient.name) }
        }
        guard let target = candidates.first(where: { $0.role == .essential }) ?? candidates.first else { return nil }

        let readiness = totalCount > 0 ? Double(readyCount) / Double(totalCount) : 0
        let status: RecipeFeasibilityStatus = readiness >= 0.5 ? .almostMakeable : .notMakeable
        return OnlineRecipeFridgeFixTarget(
            recipe: recipe,
            ingredient: target,
            feasibility: RecipeFeasibilityResult(recipe: recipe, evaluatedIngredients: [], status: status)
        )
    }
}
