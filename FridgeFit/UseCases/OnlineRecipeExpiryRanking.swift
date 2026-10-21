//
//  OnlineRecipeExpiryRanking.swift
//  FridgeFit
//

import Foundation

/// Ranks Discover results so recipes that use up soon-to-expire pantry
/// items come first.
///
/// Business rules:
/// - **One expiry authority.** Urgency comes from `ExpiryService` (today,
///   tomorrow, within 3 days = worth prioritising), never a second rule.
/// - **Expired food earns nothing.** A recipe that would use an expired
///   item sinks below everything else instead of rising - ranking it up
///   would be recommending someone eat food that has gone off. Same rule as
///   `GenerateContextAwareRecommendationsUseCase`.
/// - **Conservative name matching.** The provider's used-ingredient names
///   and pantry names are different vocabularies. They match only after
///   `OnlineIngredientName.normalized`, case folding and a plural fold on the
///   last word ("tomatoes" ↔ "Tomato"). No synonym or substring matching:
///   "coconut milk" must never claim to use up the user's milk. Missing a
///   match just means no boost; a false match would be a false claim.
/// - **No double counting.** Each pantry item is credited at most once per
///   recipe.
/// - Recipes with a usable method rank above ones without steps (the
///   provider's data is incomplete for some), once expiry has been
///   considered.
/// - Otherwise the existing order holds: fewest missing ingredients, then
///   most pantry ingredients used, then the provider's order.
nonisolated enum OnlineRecipeExpiryRanking {

    /// Pantry items worth using first (urgent but not expired), most urgent
    /// first - used to order the request and for the Discover banner.
    static func urgentPantryItems(
        in pantry: [PantryItem],
        now: Date,
        calendar: Calendar = .current
    ) -> [UrgentIngredientUse] {
        var seen = Set<String>()
        var result: [UrgentIngredientUse] = []
        for item in pantry {
            guard let state = ExpiryService.state(for: item.expiryDate, now: now, calendar: calendar),
                  state.urgency != .expired,
                  state.shouldPrioritise,
                  seen.insert(matchKey(item.name)).inserted
            else { continue }
            result.append(UrgentIngredientUse(ingredientName: item.name, urgency: state.urgency, daysUntilExpiry: state.daysUntilExpiry))
        }
        return sortedByUrgency(result)
    }

    /// Puts urgent pantry names first, keeping everything else in order.
    /// Ordering only - the same set of names is sent either way.
    static func requestOrder(names: [String], urgent: [UrgentIngredientUse]) -> [String] {
        let urgentKeys = urgent.map { matchKey($0.ingredientName) }
        let rank = Dictionary(urgentKeys.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return names.enumerated().sorted { lhs, rhs in
            let l = rank[matchKey(lhs.element)] ?? Int.max
            let r = rank[matchKey(rhs.element)] ?? Int.max
            return l != r ? l < r : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Which urgent / expired pantry items `match` would use.
    static func expiryUse(
        of match: OnlineRecipeMatch,
        pantry: [PantryItem],
        now: Date,
        calendar: Calendar = .current
    ) -> OnlineRecipeExpiryUse {
        var use = OnlineRecipeExpiryUse()
        var credited = Set<UUID>()

        for usedName in match.usedIngredientNames {
            guard let item = pantry.first(where: { namesMatch(usedName, $0.name) }),
                  credited.insert(item.id).inserted,
                  let state = ExpiryService.state(for: item.expiryDate, now: now, calendar: calendar)
            else { continue }

            if state.urgency == .expired {
                use.expired.append(item.name)
            } else if state.shouldPrioritise {
                use.urgent.append(UrgentIngredientUse(ingredientName: item.name, urgency: state.urgency, daysUntilExpiry: state.daysUntilExpiry))
            }
        }

        use.urgent = sortedByUrgency(use.urgent)
        use.expired.sort()
        return use
    }

    /// Stable ranking; see the type's business rules for the order.
    static func ranked(
        _ matches: [OnlineRecipeMatch],
        expiryUse: [Int: OnlineRecipeExpiryUse]
    ) -> [OnlineRecipeMatch] {
        matches.enumerated().sorted { lhsPair, rhsPair in
            let lhs = lhsPair.element, rhs = rhsPair.element
            let lUse = expiryUse[lhs.id] ?? .none
            let rUse = expiryUse[rhs.id] ?? .none

            if lUse.usesExpiredIngredient != rUse.usesExpiredIngredient {
                return rUse.usesExpiredIngredient
            }
            let lUrgency = lUse.mostUrgent?.rawValue ?? -1
            let rUrgency = rUse.mostUrgent?.rawValue ?? -1
            if lUrgency != rUrgency { return lUrgency > rUrgency }
            if lUse.urgent.count != rUse.urgent.count { return lUse.urgent.count > rUse.urgent.count }
            if lhs.recipe.steps.isEmpty != rhs.recipe.steps.isEmpty { return !lhs.recipe.steps.isEmpty }
            if lhs.missedIngredients.count != rhs.missedIngredients.count {
                return lhs.missedIngredients.count < rhs.missedIngredients.count
            }
            if lhs.usedIngredientNames.count != rhs.usedIngredientNames.count {
                return lhs.usedIngredientNames.count > rhs.usedIngredientNames.count
            }
            return lhsPair.offset < rhsPair.offset
        }.map(\.element)
    }

    // MARK: - Name matching

    /// Whether a provider ingredient name and a pantry name refer to the
    /// same thing, under the conservative rules above.
    static func namesMatch(_ providerName: String, _ pantryName: String) -> Bool {
        let a = matchKey(providerName)
        return !a.isEmpty && a == matchKey(pantryName)
    }

    /// Provider names first lose parenthetical notes
    /// (`OnlineIngredientName.normalized`), then go through the app-wide
    /// rule (`IngredientNameMatching`), so Discover agrees with the pantry.
    static func matchKey(_ name: String) -> String {
        IngredientNameMatching.matchKey(OnlineIngredientName.normalized(name))
    }

    private static func sortedByUrgency(_ uses: [UrgentIngredientUse]) -> [UrgentIngredientUse] {
        uses.sorted {
            $0.urgency.rawValue != $1.urgency.rawValue
                ? $0.urgency.rawValue > $1.urgency.rawValue
                : $0.ingredientName < $1.ingredientName
        }
    }
}
