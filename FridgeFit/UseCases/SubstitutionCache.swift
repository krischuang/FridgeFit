//
//  SubstitutionCache.swift
//  FridgeFit
//

import Foundation

/// Identifies one substitution request's cacheable result: which recipe,
/// which ingredient, and a fingerprint of the pantry at request time.
///
/// `pantryFingerprint` changing (because the pantry changed) is what
/// invalidates a cache entry - there's no explicit expiry.
///
/// ## Why the recipe's title and not its id
///
/// `Recipe.id` defaults to a fresh `UUID`, and `BundledRecipeRepository`
/// takes that default - so the same recipe has a different id in every
/// launch. A key built on it can only ever be hit within one process, which
/// is fine for a purely in-memory cache and useless for a persisted one.
/// The normalised title is stable across launches and is also what the
/// prompt actually receives as recipe context, so it identifies the request
/// at exactly the granularity the answer depends on.
nonisolated struct SubstitutionCacheKey: Hashable {
    let recipeTitle: String
    let ingredientName: String
    let pantryFingerprint: String

    /// - Parameters:
    ///   - recipeTitle: normalised here rather than at the call site, so
    ///     casing or stray whitespace can't split one recipe into two
    ///     entries.
    init(recipeTitle: String, ingredientName: String, pantryFingerprint: String) {
        self.recipeTitle = Self.normalized(recipeTitle)
        self.ingredientName = Self.normalized(ingredientName)
        self.pantryFingerprint = pantryFingerprint
    }

    /// The same identity flattened into one string, for a store that keys by
    /// `String`. `|` separates the parts and appears in none of them.
    var persistentKey: String {
        [recipeTitle, ingredientName, pantryFingerprint].joined(separator: "|")
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Keeps "find substitute" answers so re-opening the same prompt against an
/// unchanged pantry doesn't make the model generate them again.
///
/// Two layers, both optional to the caller:
/// - An in-memory dictionary, which is all previews and tests use.
/// - A `SubstitutionCacheStoring` the app passes in, which survives both the
///   instance and the launch. Every screen builds its own `SubstitutionCache`,
///   so without it a cache hit only happens on the screen that paid for the
///   generation, and only until the app restarts.
///
/// `SubstitutionCache()` is therefore still a plain in-process cache, and
/// `SubstitutionCache.persistent()` is the one the running app wires up.
nonisolated final class SubstitutionCache {
    private var storage: [SubstitutionCacheKey: [SubstitutionSuggestion]] = [:]
    private let persistentStore: SubstitutionCacheStoring?

    /// - Parameter persistentStore: `nil` (the default) keeps the cache
    ///   entirely in memory, which is what previews and tests want - a
    ///   shared file would otherwise leak results between test runs.
    init(persistentStore: SubstitutionCacheStoring? = nil) {
        self.persistentStore = persistentStore
    }

    /// The app's cache: in-memory, backed by the on-disk store.
    static func persistent() -> SubstitutionCache {
        SubstitutionCache(persistentStore: SubstitutionCacheStore())
    }

    /// Promotes a persisted hit into memory, so the second ask in this
    /// process doesn't re-read the file.
    func suggestions(for key: SubstitutionCacheKey) -> [SubstitutionSuggestion]? {
        if let inMemory = storage[key] { return inMemory }
        guard let persisted = persistentStore?.loadSuggestions(forKey: key.persistentKey) else {
            return nil
        }
        storage[key] = persisted
        return persisted
    }

    func store(_ suggestions: [SubstitutionSuggestion], for key: SubstitutionCacheKey) {
        storage[key] = suggestions

        // An empty result is remembered for this launch but never written to
        // disk. "No usable substitute" is usually the validator rejecting
        // everything the model produced, and that is worth retrying after a
        // relaunch rather than baking into the cache permanently.
        guard !suggestions.isEmpty else { return }
        persistentStore?.save(suggestions, forKey: key.persistentKey)
    }

    /// A fingerprint of the pantry's contents, used as part of the cache key.
    ///
    /// Deliberately not `Hasher`: its seed is randomised per process, so the
    /// hash of an unchanged pantry differs between launches and no persisted
    /// entry would ever match. This is FNV-1a, which is fixed by its
    /// constants and therefore reproducible - a cache key, not a checksum,
    /// and never used for anything that needs collision resistance.
    static func pantryFingerprint(_ pantryItems: [PantryItem]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x1000_0000_01b3

        func feed(_ string: String) {
            for byte in Array(string.utf8) + [0] {
                hash ^= UInt64(byte)
                hash = hash &* prime
            }
        }

        for item in pantryItems.sorted(by: { $0.name.lowercased() < $1.name.lowercased() }) {
            feed(item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            feed(String(item.quantity))
            feed(item.unit.rawValue)
        }
        return String(hash, radix: 16)
    }
}
