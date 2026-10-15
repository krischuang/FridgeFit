//
//  CompositeRecipeRepository.swift
//  FridgeFit
//

import Foundation

/// One `RecipeRepository` over several stores, so the recommendation flow
/// sees the bundled catalogue and anything the user saved from Discover as a
/// single list.
///
/// ## Why this is the whole integration
///
/// `GenerateContextAwareRecommendationsUseCase` reads exactly one
/// `RecipeRepository`. That is the right shape - one catalogue, one pantry
/// snapshot, one ranking - and it is why there is no second recommendation
/// engine anywhere in this feature. Making saved online recipes
/// participate therefore needs no change to the engine, the suitability
/// evaluator, the feasibility engine or the ranking comparator: it needs a
/// repository that reads from two places. This is that type.
///
/// Because `SaveOnlineRecipeUseCase` has already converted online data into
/// ordinary `Recipe` values, everything downstream treats a saved recipe
/// exactly like a bundled one - quantity-aware feasibility, expiry-aware
/// suitability, context filtering, ranking reasons and session feedback all
/// apply unchanged.
///
/// ## Primary and supplementary sources
///
/// The split exists because the two kinds of failure deserve different
/// answers:
///
/// - The **primary** source is the bundled catalogue. If it cannot be read
///   there is nothing to recommend, so its error propagates and the
///   recommendation screen reports `recipeCatalogueUnavailable` as it
///   always has.
/// - A **supplementary** source is additive. If the saved-recipe store is
///   unreachable - offline, signed out, rules not yet deployed - degrading
///   to the bundled catalogue is strictly better than failing the whole
///   screen, so its error is swallowed and recorded in
///   `lastSupplementaryFailure` for callers that want to surface it. A user
///   who has saved nothing is in this position by definition, and it would
///   be absurd for that to break recommendations.
///
/// ## Ordering and duplicates
///
/// Results are primary-first, then each supplementary source in order, with
/// the first occurrence of a `Recipe.id` winning. Ordering is not load-
/// bearing for recommendations - the ranking comparator imposes a total
/// order of its own - but a deterministic concatenation keeps tests
/// assertable. De-duplication matters more: feeding the same recipe twice
/// would let one dish occupy two slots in a ranked list, and
/// `SessionRecommendationInfluence` keys feedback on `Recipe.id`, so a
/// duplicate would take two skips to dismiss.
nonisolated final class CompositeRecipeRepository: RecipeRepository {

    private let primary: RecipeRepository
    private let supplementary: [RecipeRepository]

    /// The most recent supplementary read failure, or `nil` if the last
    /// `fetchAll()` had none. Not thrown - see the type's discussion.
    private(set) var lastSupplementaryFailure: Error?

    init(primary: RecipeRepository, supplementary: [RecipeRepository] = []) {
        self.primary = primary
        self.supplementary = supplementary
    }

    /// Convenience for the app's composition root: the bundled catalogue
    /// plus an optional saved-recipe store.
    ///
    /// Passing `nil` for `savedRecipes` - which is what happens while
    /// `OnlineRecipeFeature.savedRecipeStorage` is gated off - yields a
    /// repository that behaves identically to `bundled` alone. That is the
    /// property that makes wiring this in today a no-op for existing
    /// behaviour.
    convenience init(bundled: RecipeRepository, savedRecipes: SavedRecipeRepository?) {
        self.init(
            primary: bundled,
            supplementary: savedRecipes.map { [$0] } ?? []
        )
    }

    func fetchAll() async throws -> [Recipe] {
        let primaryRecipes = try await primary.fetchAll()

        var failure: Error?
        var combined = primaryRecipes
        for source in supplementary {
            do {
                combined.append(contentsOf: try await source.fetchAll())
            } catch {
                failure = error
            }
        }
        lastSupplementaryFailure = failure

        return Self.deduplicatedByID(combined)
    }

    /// First occurrence of each `Recipe.id` wins, input order preserved.
    static func deduplicatedByID(_ recipes: [Recipe]) -> [Recipe] {
        var seen = Set<UUID>()
        var result: [Recipe] = []
        result.reserveCapacity(recipes.count)
        for recipe in recipes where seen.insert(recipe.id).inserted {
            result.append(recipe)
        }
        return result
    }
}
