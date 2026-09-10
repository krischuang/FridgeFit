//
//  SubstitutionCache.swift
//  FridgeFit
//

import Foundation

/// Identifies one substitution request's cacheable result: which recipe,
/// which ingredient, and a snapshot of the pantry at request time.
///
/// `pantrySnapshotHash` changing (because the pantry changed) is what
/// invalidates a cache entry - there's no explicit expiry or eviction.
struct SubstitutionCacheKey: Hashable {
    let recipeID: UUID
    let ingredientName: String
    let pantrySnapshotHash: Int
}

/// A simple in-memory cache so re-opening the same "find substitute" prompt
/// against an unchanged pantry doesn't make another provider call.
///
/// Deliberately not persisted across launches, and deliberately not an
/// LRU or size-bounded cache - Phase 3's usage pattern (one recipe detail
/// screen at a time) doesn't need that.
final class SubstitutionCache {
    private var storage: [SubstitutionCacheKey: [SubstitutionSuggestion]] = [:]

    func suggestions(for key: SubstitutionCacheKey) -> [SubstitutionSuggestion]? {
        storage[key]
    }

    func store(_ suggestions: [SubstitutionSuggestion], for key: SubstitutionCacheKey) {
        storage[key] = suggestions
    }

    /// A stable-within-this-process hash of the pantry's contents, used as
    /// part of the cache key. Not meant to be stable across launches -
    /// `Hasher`'s seed is randomized per process, which is fine since the
    /// cache itself doesn't persist across launches either.
    static func pantrySnapshotHash(_ pantryItems: [PantryItem]) -> Int {
        var hasher = Hasher()
        for item in pantryItems.sorted(by: { $0.name.lowercased() < $1.name.lowercased() }) {
            hasher.combine(item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            hasher.combine(item.quantity)
            hasher.combine(item.unit)
        }
        return hasher.finalize()
    }
}
