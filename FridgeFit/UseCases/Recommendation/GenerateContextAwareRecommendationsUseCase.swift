//
//  GenerateContextAwareRecommendationsUseCase.swift
//  FridgeFit
//

import Foundation

/// Produces a ranked, explainable list of meals for the user's current
/// pantry and cooking context.
///
/// ## The pipeline
///
/// ```
/// PantryRepository  ──┐
///                     ├─> EvaluateRecipeFeasibilityUseCase   (quantities, units)
/// RecipeRepository  ──┘              │
///                                    v
///                     EvaluateRecipeSuitabilityUseCase        (context, readiness, expiry)
///                                    │
///                                    v
///                     ranking comparator + ranking reasons    (this type)
///                                    │
///                                    v
///                         [RecipeRecommendation]
/// ```
///
/// Both repositories are the ones the rest of the app already uses, passed
/// in. There is no local sample store and no singleton: a recommendation
/// run reads the same Firestore-backed pantry as the Pantry tab, the
/// Kitchen tab and the receipt scanner, under the same auth.
///
/// ## Concurrency
///
/// `nonisolated`, so the ranking - a comparator over every surviving
/// recipe - runs off the main actor. The two repository reads are `await`ed
/// once each up front; the pantry is deliberately **not** re-read per
/// recipe, both to avoid N round trips and so every recipe in one list is
/// ranked against one consistent pantry snapshot.
nonisolated struct GenerateContextAwareRecommendationsUseCase {

    private let recipeRepository: RecipeRepository
    private let pantryRepository: PantryRepository
    private let suitabilityEvaluator: EvaluateRecipeSuitabilityUseCase

    init(
        recipeRepository: RecipeRepository,
        pantryRepository: PantryRepository,
        suitabilityEvaluator: EvaluateRecipeSuitabilityUseCase = EvaluateRecipeSuitabilityUseCase()
    ) {
        self.recipeRepository = recipeRepository
        self.pantryRepository = pantryRepository
        self.suitabilityEvaluator = suitabilityEvaluator
    }

    /// Generates recommendations, best first.
    ///
    /// - Parameters:
    ///   - context: The user's current constraints and preferences.
    ///   - session: Feedback recorded in this session, which hides skipped
    ///     recipes and reorders the rest. Pass `nil` for an uninfluenced
    ///     run.
    ///   - now: The instant expiry is measured from.
    /// - Throws: `RecommendationGenerationError` when the run cannot
    ///   produce anything to show, with a case that says which.
    func execute(
        context: CookingContext,
        session: RecommendationSession? = nil,
        now: Date = .now
    ) async throws -> [RecipeRecommendation] {

        let pantryItems: [PantryItem]
        do {
            pantryItems = try await pantryRepository.fetchAll()
        } catch {
            throw RecommendationGenerationError.pantryInformationUnavailable
        }

        guard !pantryItems.isEmpty else {
            throw RecommendationGenerationError.pantryNeedsIngredients
        }

        let recipes: [Recipe]
        do {
            recipes = try await recipeRepository.fetchAll()
        } catch {
            throw RecommendationGenerationError.recipeCatalogueUnavailable
        }

        guard !recipes.isEmpty else {
            throw RecommendationGenerationError.recipeCatalogueEmpty
        }

        try Task.checkCancellation()

        let influence = SessionRecommendationInfluence(
            session: session,
            recipes: recipes
        )

        var recommendations: [RecipeRecommendation] = []
        var exclusionReasons: [RecipeExclusionReason] = []
        var skippedRecipeCount = 0
        var evaluatedRecipeCount = 0

        for recipe in recipes {
            if influence.excludes(recipe) {
                skippedRecipeCount += 1
                continue
            }

            evaluatedRecipeCount += 1

            // One feasibility engine, one pantry snapshot.
            let feasibility = EvaluateRecipeFeasibilityUseCase.evaluate(
                recipe: recipe,
                against: pantryItems
            )

            let outcome = suitabilityEvaluator.execute(
                recipe: recipe,
                feasibility: feasibility,
                pantryItems: pantryItems,
                context: context,
                now: now
            )

            switch outcome {
            case .excluded(let reason):
                exclusionReasons.append(reason)
            case .suitable(let suitability):
                recommendations.append(
                    RecipeRecommendation(
                        suitability: suitability,
                        rankingReasons: Self.rankingReasons(
                            for: suitability,
                            context: context
                        )
                    )
                )
            }
        }

        guard !recommendations.isEmpty else {
            throw RecommendationGenerationError.emptyResult(
                exclusionReasons: exclusionReasons,
                skippedRecipeCount: skippedRecipeCount,
                evaluatedRecipeCount: evaluatedRecipeCount
            )
        }

        try Task.checkCancellation()

        return recommendations.sorted {
            Self.isHigherPriority($0, than: $1, context: context, influence: influence)
        }
    }

    // MARK: - Explanations

    /// The reasons shown under a recommendation.
    ///
    /// Every one is gated on a fact that was actually established. In
    /// particular `readyToCook` comes from the feasibility status rather
    /// than from a name match, and no reason is produced from metadata the
    /// recipe never stated - `fitsCookingTime` requires a stated time, and
    /// `matchesDietaryRestrictions` requires labels plus a selected
    /// restriction, so neither can appear on an unlabelled recipe.
    static func rankingReasons(
        for suitability: RecipeSuitability,
        context: CookingContext
    ) -> [RecommendationReason] {
        var reasons: [RecommendationReason] = []
        let recipe = suitability.recipe

        if suitability.readiness == .readyToCook {
            reasons.append(.readyToCook)
        }

        if context.prioritisesExpiringIngredients && suitability.usesUrgentIngredient {
            reasons.append(.usesIngredientExpiringSoon)
        }

        // Only when there is genuinely something small to buy. A recipe
        // needing nothing already says `readyToCook`, and saying "needs
        // only one more ingredient" there would be wrong.
        if suitability.shoppingIngredients.count == 1 {
            reasons.append(.minimalShopping)
        }

        if recipe.matchesCuisine(in: context.preferredCuisines) {
            reasons.append(.matchesCuisinePreference)
        }

        if recipe.matchesTaste(in: context.preferredTastes) {
            reasons.append(.matchesTastePreference)
        }

        if recipe.fitsCookingTime(within: context.maximumCookingTime) == true {
            reasons.append(.fitsCookingTime)
        }

        if recipe.fitsDifficulty(atMost: context.maximumDifficulty) == true {
            reasons.append(.fitsDifficulty)
        }

        if !context.dietaryRestrictions.isEmpty,
           suitability.dietaryCompliance == .satisfied {
            reasons.append(.matchesDietaryRestrictions)
        }

        if suitability.pantryMatchPercentage >= EvaluateRecipeSuitabilityUseCase.strongPantryMatchThreshold {
            reasons.append(.strongPantryMatch)
        }

        return reasons
    }

    // MARK: - Ranking

    /// The ranking comparator, ported from the source branch and extended
    /// with a total tiebreak.
    ///
    /// Ordered by how much the user is likely to care, and every step is a
    /// fact rather than a weight - which is what lets the recommendation
    /// screen explain the order it produced:
    ///
    /// 1. Session feedback rank (reported down, saved up).
    /// 2. Session-stated preferences for shorter / easier recipes.
    /// 3. Food about to go off, when the user asked to prioritise it -
    ///    including the source's rule that a nearly-ready urgent recipe
    ///    outranks a fully-ready one that wastes nothing.
    /// 4. Recipes using already-expired food sink, never rise.
    /// 5. Readiness, then shopping effort.
    /// 6. Cuisine, then taste preference.
    /// 7. Stated cooking time, shorter first; unstated sorts last.
    /// 8. Pantry coverage.
    /// 9. Title, then id - so the order is **total**. Without this last
    ///    step two equally good recipes could swap places between runs,
    ///    which makes the list feel random and the tests unassertable.
    static func isHigherPriority(
        _ first: RecipeRecommendation,
        than second: RecipeRecommendation,
        context: CookingContext,
        influence: SessionRecommendationInfluence
    ) -> Bool {
        let a = first.suitability
        let b = second.suitability

        let feedbackRank = (influence.rank(a), influence.rank(b))
        if feedbackRank.0 != feedbackRank.1 {
            return feedbackRank.0 > feedbackRank.1
        }

        if influence.prefersShorterRecipes {
            let times = (a.recipe.totalCookingTimeInMinutes, b.recipe.totalCookingTimeInMinutes)
            if times.0 != times.1 {
                return Self.isSooner(times.0, than: times.1)
            }
        }

        if influence.prefersEasierRecipes {
            let difficulties = (a.recipe.difficulty, b.recipe.difficulty)
            if difficulties.0 != difficulties.1 {
                return Self.isEasier(difficulties.0, than: difficulties.1)
            }
        }

        if context.prioritisesExpiringIngredients {
            // The source branch's deliberate inversion: a recipe that
            // rescues food about to go off is worth one small shop,
            // because the alternative is throwing the food away.
            if a.readiness != .readyToCook, a.usesUrgentIngredient,
               b.readiness == .readyToCook, !b.usesUrgentIngredient {
                return true
            }

            if b.readiness != .readyToCook, b.usesUrgentIngredient,
               a.readiness == .readyToCook, !a.usesUrgentIngredient {
                return false
            }

            if a.usesUrgentIngredient != b.usesUrgentIngredient {
                return a.usesUrgentIngredient
            }
        }

        // Independent of the user's expiry preference: a dish that would
        // use food already past its date is never promoted over one that
        // wouldn't.
        if a.usesExpiredIngredient != b.usesExpiredIngredient {
            return b.usesExpiredIngredient
        }

        let readiness = (Self.readinessRank(a.readiness), Self.readinessRank(b.readiness))
        if readiness.0 != readiness.1 {
            return readiness.0 > readiness.1
        }

        if a.shoppingIngredients.count != b.shoppingIngredients.count {
            return a.shoppingIngredients.count < b.shoppingIngredients.count
        }

        let cuisineMatch = (
            a.recipe.matchesCuisine(in: context.preferredCuisines),
            b.recipe.matchesCuisine(in: context.preferredCuisines)
        )
        if cuisineMatch.0 != cuisineMatch.1 {
            return cuisineMatch.0
        }

        let tasteMatch = (
            a.recipe.matchesTaste(in: context.preferredTastes),
            b.recipe.matchesTaste(in: context.preferredTastes)
        )
        if tasteMatch.0 != tasteMatch.1 {
            return tasteMatch.0
        }

        let times = (a.recipe.totalCookingTimeInMinutes, b.recipe.totalCookingTimeInMinutes)
        if times.0 != times.1 {
            return Self.isSooner(times.0, than: times.1)
        }

        if a.pantryMatchPercentage != b.pantryMatchPercentage {
            return a.pantryMatchPercentage > b.pantryMatchPercentage
        }

        if a.recipe.title != b.recipe.title {
            return a.recipe.title < b.recipe.title
        }

        return a.recipe.id.uuidString < b.recipe.id.uuidString
    }

    /// Compares two possibly-unstated cooking times, shorter first.
    ///
    /// An unstated time sorts after any stated one. It is not treated as
    /// zero (which would rank unlabelled recipes first on no evidence) nor
    /// as infinity in the filter (which would exclude them) - see
    /// `EvaluateRecipeSuitabilityUseCase`.
    private static func isSooner(_ lhs: Int?, than rhs: Int?) -> Bool {
        switch (lhs, rhs) {
        case (let left?, let right?): return left < right
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): return false
        }
    }

    /// Compares two possibly-unstated difficulties, easier first, with
    /// unstated sorting last for the same reason as `isSooner`.
    private static func isEasier(_ lhs: CookingDifficulty?, than rhs: CookingDifficulty?) -> Bool {
        switch (lhs, rhs) {
        case (let left?, let right?): return left < right
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): return false
        }
    }

    private static func readinessRank(_ readiness: RecipeReadiness) -> Int {
        switch readiness {
        case .readyToCook: return 3
        case .almostReady: return 2
        case .needsOneToTwoIngredients: return 1
        }
    }
}

/// The deterministic, session-only effect of feedback the user gave during
/// this recommendation flow.
///
/// Built once per run from a `RecommendationSession` and the current
/// catalogue, so ranking depends on nothing but its inputs. Holds recipe
/// ids and metadata read from recipes - it never mutates a `Recipe` or a
/// `PantryItem`, so no amount of skipping or reporting can corrupt stored
/// data.
nonisolated struct SessionRecommendationInfluence: Equatable {

    private let skippedRecipeIDs: Set<UUID>
    private let promotedCuisines: Set<Cuisine>
    private let promotedTastes: Set<TastePreference>
    private let deprioritisedCuisines: Set<Cuisine>
    private let deprioritisedTastes: Set<TastePreference>
    private let deprioritisesShopping: Bool
    /// The easiest difficulty the user has called too difficult. Anything
    /// at or above it is deprioritised.
    private let difficultRecipeThreshold: CookingDifficulty?

    let prefersShorterRecipes: Bool
    let prefersEasierRecipes: Bool

    init(session: RecommendationSession?, recipes: [Recipe]) {
        guard let session, session.isActive, !session.recordedFeedback.isEmpty else {
            skippedRecipeIDs = []
            promotedCuisines = []
            promotedTastes = []
            deprioritisedCuisines = []
            deprioritisedTastes = []
            deprioritisesShopping = false
            difficultRecipeThreshold = nil
            prefersShorterRecipes = false
            prefersEasierRecipes = false
            return
        }

        let recipesByID = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var skipped: Set<UUID> = []
        var promotedCuisines: Set<Cuisine> = []
        var promotedTastes: Set<TastePreference> = []
        var deprioritisedCuisines: Set<Cuisine> = []
        var deprioritisedTastes: Set<TastePreference> = []
        var deprioritisesShopping = false
        var difficultThreshold: CookingDifficulty?
        var prefersShorter = false
        var prefersEasier = false

        // Sorted so the fold is order-independent: a dictionary's
        // iteration order is not stable between runs, and two "too
        // difficult" reports must produce the same threshold either way.
        for recipeID in session.recordedFeedback.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let action = session.recordedFeedback[recipeID] else { continue }
            let recipe = recipesByID[recipeID]

            switch action {
            case .saved:
                if let cuisine = recipe?.cuisine {
                    promotedCuisines.insert(cuisine)
                }
                if let tastes = recipe?.tastePreferences {
                    promotedTastes.formUnion(tastes)
                }

            case .skipped:
                skipped.insert(recipeID)

            case .reported(let reason):
                switch reason {
                case .tooMuchShopping:
                    deprioritisesShopping = true

                case .takesTooLong:
                    prefersShorter = true

                case .tooDifficult:
                    prefersEasier = true
                    if let difficulty = recipe?.difficulty {
                        difficultThreshold = min(difficultThreshold ?? difficulty, difficulty)
                    }

                case .notMyTaste:
                    if let cuisine = recipe?.cuisine {
                        deprioritisedCuisines.insert(cuisine)
                    }
                    if let tastes = recipe?.tastePreferences {
                        deprioritisedTastes.formUnion(tastes)
                    }
                }
            }
        }

        self.skippedRecipeIDs = skipped
        self.promotedCuisines = promotedCuisines
        self.promotedTastes = promotedTastes
        self.deprioritisedCuisines = deprioritisedCuisines
        self.deprioritisedTastes = deprioritisedTastes
        self.deprioritisesShopping = deprioritisesShopping
        self.difficultRecipeThreshold = difficultThreshold
        self.prefersShorterRecipes = prefersShorter
        self.prefersEasierRecipes = prefersEasier
    }

    /// Whether feedback should hide this recipe entirely.
    ///
    /// Only an explicit skip does this. A report reorders but keeps the
    /// recipe visible, so the user can still see why it was ranked low.
    func excludes(_ recipe: Recipe) -> Bool {
        skippedRecipeIDs.contains(recipe.id)
    }

    /// A feedback rank for one suitable recipe; higher sorts earlier.
    ///
    /// Negative feedback beats positive similarity on purpose: if the user
    /// has just said a cuisine is not to their taste, a recipe in that
    /// cuisine must not stay at the top because some *other* saved recipe
    /// shared a taste with it.
    func rank(_ suitability: RecipeSuitability) -> Int {
        if isDeprioritised(suitability) { return 0 }
        if isPromoted(suitability.recipe) { return 2 }
        return 1
    }

    private func isPromoted(_ recipe: Recipe) -> Bool {
        if let cuisine = recipe.cuisine, promotedCuisines.contains(cuisine) {
            return true
        }
        if let tastes = recipe.tastePreferences, !promotedTastes.isDisjoint(with: tastes) {
            return true
        }
        return false
    }

    private func isDeprioritised(_ suitability: RecipeSuitability) -> Bool {
        if deprioritisesShopping, !suitability.shoppingIngredients.isEmpty {
            return true
        }

        if let difficultRecipeThreshold,
           let difficulty = suitability.recipe.difficulty,
           difficulty >= difficultRecipeThreshold {
            return true
        }

        if let cuisine = suitability.recipe.cuisine, deprioritisedCuisines.contains(cuisine) {
            return true
        }

        if let tastes = suitability.recipe.tastePreferences,
           !deprioritisedTastes.isDisjoint(with: tastes) {
            return true
        }

        return false
    }
}
