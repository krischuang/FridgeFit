//
//  EvaluateRecipeSuitabilityUseCase.swift
//  FridgeFit
//

import Foundation

/// Decides whether one recipe is worth offering in the current context,
/// and how close to cookable it is.
///
/// ## What this does and does not decide
///
/// It does **not** decide whether an ingredient is available. That is
/// `EvaluateRecipeFeasibilityUseCase`'s job, and this use case takes its
/// `RecipeFeasibilityResult` as an input it is not allowed to second-guess.
/// The branch this feature came from did its own ingredient matching by
/// name, which meant a pantry holding one gram of chicken satisfied a
/// recipe needing four hundred. Keeping the two responsibilities apart is
/// what makes "ready to cook" mean a converted, compared quantity rather
/// than a string match.
///
/// What it adds on top is context: the user's hard constraints (diet, time,
/// difficulty), a readiness reading of the feasibility status, and the
/// expiry facts behind an "uses something expiring soon" claim.
///
/// `nonisolated` and stateless, so a run over the whole catalogue happens
/// off the main actor.
nonisolated struct EvaluateRecipeSuitabilityUseCase {

    /// How many unresolved essential ingredients are still treated as a
    /// small shop rather than a reason to hide the recipe.
    ///
    /// Two, matching the source branch's rule. Above that the recipe is
    /// excluded as `requiresMoreThanTwoIngredients`.
    static let maximumShoppingIngredients = 2

    /// Coverage at or above which a recipe earns `strongPantryMatch`.
    static let strongPantryMatchThreshold = 80

    init() {}

    /// Evaluates one recipe.
    ///
    /// - Parameters:
    ///   - recipe: The dish being considered.
    ///   - feasibility: The verdict from `EvaluateRecipeFeasibilityUseCase`
    ///     for this same recipe and pantry. Must be the result for
    ///     `recipe`; passing another recipe's result is a programmer error.
    ///   - pantryItems: The pantry the feasibility result was computed
    ///     from, needed here only to read expiry dates.
    ///   - context: The user's current constraints and preferences.
    ///   - now: The instant expiry urgency is measured from. Injected so
    ///     the "expired" and "expiring soon" boundaries are testable
    ///     without waiting for midnight.
    func execute(
        recipe: Recipe,
        feasibility: RecipeFeasibilityResult,
        pantryItems: [PantryItem],
        context: CookingContext,
        now: Date = .now
    ) -> RecipeSuitabilityOutcome {

        // MARK: Hard constraints, strictest first

        // Diet before anything else: a recipe someone cannot eat should
        // never be ruled out "because it takes too long", which would
        // imply a shorter version would be fine.
        let compliance = recipe.dietaryCompliance(with: context.dietaryRestrictions)
        switch compliance {
        case .violated(let missing):
            return .excluded(.dietaryRestrictionConflict(missing: missing))
        case .unknown:
            // Withheld rather than offered with a caveat. See
            // `DietaryCompliance` - an unlabelled recipe is not evidence.
            return .excluded(.dietaryComplianceUnknown)
        case .satisfied:
            break
        }

        // Unstated time and difficulty do *not* exclude. They are
        // non-safety preferences, and excluding every unlabelled recipe
        // would empty the list for anyone who set a limit - the failure
        // mode this integration was explicitly asked to avoid. An
        // unstated value simply earns no ranking credit below.
        if recipe.fitsCookingTime(within: context.maximumCookingTime) == false {
            return .excluded(.cookingTimeExceedsLimit)
        }

        if recipe.fitsDifficulty(atMost: context.maximumDifficulty) == false {
            return .excluded(.difficultyExceedsLimit)
        }

        // MARK: Readiness, read from the feasibility verdict

        let shoppingIngredients = feasibility.evaluatedIngredients
            .filter { $0.role == .essential }
            .filter { $0.availability == .missing || $0.availability == .insufficient }
            .map(\.ingredient.name)

        let unverifiedIngredients = feasibility.evaluatedIngredients
            .filter { $0.role == .essential && $0.availability == .quantityUnverified }
            .map(\.ingredient.name)

        guard shoppingIngredients.count <= Self.maximumShoppingIngredients else {
            return .excluded(.requiresMoreThanTwoIngredients)
        }

        let readiness = Self.readiness(
            for: feasibility,
            shoppingIngredientCount: shoppingIngredients.count,
            unverifiedIngredientCount: unverifiedIngredients.count
        )

        // MARK: Expiry facts

        let expiry = Self.expiryUse(
            of: recipe,
            feasibility: feasibility,
            pantryItems: pantryItems,
            now: now
        )

        return .suitable(
            RecipeSuitability(
                recipe: recipe,
                feasibility: feasibility,
                readiness: readiness,
                shoppingIngredients: shoppingIngredients,
                unverifiedIngredients: unverifiedIngredients,
                urgentIngredients: expiry.urgent,
                expiredIngredients: expiry.expired,
                dietaryCompliance: compliance
            )
        )
    }

    // MARK: - Readiness

    /// Maps main's feasibility verdict onto a readiness reading.
    ///
    /// The ordering of these checks is the whole point:
    ///
    /// 1. `.makeable` is the only route to `readyToCook`, because it is the
    ///    only state in which every essential amount was converted and
    ///    found sufficient.
    /// 2. Nothing to buy but something unverifiable is `almostReady` - the
    ///    user has the ingredient, so this is not shopping, but the amount
    ///    was never confirmed so it must not read as "ready".
    /// 3. Anything else here is one or two things short. The
    ///    more-than-two case was already excluded by the caller.
    static func readiness(
        for feasibility: RecipeFeasibilityResult,
        shoppingIngredientCount: Int,
        unverifiedIngredientCount: Int
    ) -> RecipeReadiness {
        if feasibility.status == .makeable {
            return .readyToCook
        }

        if shoppingIngredientCount == 0 && unverifiedIngredientCount > 0 {
            return .almostReady
        }

        return .needsOneToTwoIngredients
    }

    // MARK: - Expiry

    /// Which pantry items this recipe would actually use are near expiry,
    /// and which have already gone off.
    ///
    /// Three rules worth stating explicitly:
    ///
    /// - **One expiry authority.** Urgency comes from `ExpiryService`, the
    ///   same call the Kitchen screen's "Use First" section makes, so a
    ///   recipe can never call something urgent that the Kitchen tab calls
    ///   fine. The source branch had its own flat "expires within two
    ///   days" rule; it is not reimplemented here.
    /// - **Expired food earns nothing.** `.expired` is filtered out of the
    ///   urgent list and collected separately. Ranking a dish *up* for
    ///   using food that has gone off would be recommending that someone
    ///   eat it.
    /// - **No double counting.** Only ingredients the feasibility result
    ///   actually resolved to a pantry item are considered, and each
    ///   pantry item is credited at most once even if two ingredient rows
    ///   resolve to it.
    static func expiryUse(
        of recipe: Recipe,
        feasibility: RecipeFeasibilityResult,
        pantryItems: [PantryItem],
        now: Date
    ) -> (urgent: [UrgentIngredientUse], expired: [String]) {

        var urgent: [UrgentIngredientUse] = []
        var expired: [String] = []
        var creditedItemIDs: Set<UUID> = []

        for evaluation in feasibility.evaluatedIngredients {
            // An ingredient the pantry doesn't hold cannot be urgent. This
            // also keeps a missing ingredient from matching a same-named
            // item that isn't really there.
            guard evaluation.availability != .missing else { continue }

            guard let item = pantryItems.first(where: {
                $0.ingredient.matches(name: evaluation.ingredient.name)
            }) else { continue }

            guard creditedItemIDs.insert(item.id).inserted else { continue }

            guard let state = item.expiryState else { continue }

            if state.urgency == .expired {
                expired.append(item.name)
                continue
            }

            guard state.shouldPrioritise else { continue }

            urgent.append(
                UrgentIngredientUse(
                    ingredientName: item.name,
                    urgency: state.urgency,
                    daysUntilExpiry: state.daysUntilExpiry
                )
            )
        }

        // Most urgent first, then by name so the order is total and the
        // explanation text is stable between runs.
        urgent.sort {
            $0.urgency.rawValue != $1.urgency.rawValue
                ? $0.urgency.rawValue > $1.urgency.rawValue
                : $0.ingredientName < $1.ingredientName
        }

        return (urgent, expired.sorted())
    }
}
