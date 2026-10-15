//
//  CachingOnlineRecipeService.swift
//  FridgeFit
//

import Foundation

/// An `OnlineRecipeService` decorator that keeps the last successful search
/// per query and serves it back when - and only when - the network is
/// unreachable.
///
/// Business rules (same as LettuceDecide's `CachingRecipeRepository`):
/// - A fresh, non-empty result is returned as-is and written to the cache.
/// - Only connectivity failures (`.network`, `.timeout`) fall back to the
///   cache. A bad key, used-up quota or malformed response is a real problem
///   and propagates untouched - old data must not hide it.
/// - Empty results are never cached.
/// - Cache hits come back with `isFromCache == true` so the UI can say the
///   data may be stale.
nonisolated final class CachingOnlineRecipeService: OnlineRecipeService {
    private let wrapped: OnlineRecipeService
    private let cache: OnlineRecipeCacheStoring

    init(wrapping wrapped: OnlineRecipeService, cache: OnlineRecipeCacheStoring) {
        self.wrapped = wrapped
        self.cache = cache
    }

    func searchRecipes(matching criteria: OnlineRecipeSearchCriteria) async throws -> [OnlineRecipeMatch] {
        let key = Self.cacheKey(for: criteria)
        do {
            let fresh = try await wrapped.searchRecipes(matching: criteria)
            if !fresh.isEmpty {
                cache.save(fresh, forKey: key)
            }
            return fresh
        } catch let error as OnlineRecipeSearchError where error.isConnectivityFailure {
            guard let cached = cache.loadMatches(forKey: key), !cached.isEmpty else {
                throw error
            }
            return cached.map { match in
                var match = match
                match.isFromCache = true
                return match
            }
        }
    }

    /// A stable, order-independent key for "the same query": normalised
    /// pantry names plus every filter that changes the request.
    static func cacheKey(for criteria: OnlineRecipeSearchCriteria) -> String {
        let names = Set(criteria.pantryIngredientNames.map(OnlineRecipeIngredient.normalized)).sorted()
        let preferences = criteria.preferences
        return [
            names.joined(separator: ","),
            preferences.diet.rawValue,
            preferences.intolerances.map(\.rawValue).sorted().joined(separator: ","),
            preferences.maxReadyTimeMinutes.map(String.init) ?? "-",
            String(criteria.resultLimit),
        ].joined(separator: "|")
    }
}
