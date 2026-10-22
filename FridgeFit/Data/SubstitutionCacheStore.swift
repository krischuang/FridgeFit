//
//  SubstitutionCacheStore.swift
//  FridgeFit
//

import Foundation

/// Stores validated substitution suggestions per request key so the same
/// "Find Substitute" question doesn't pay for a second generation. See
/// `SubstitutionCacheKey.persistentKey`.
nonisolated protocol SubstitutionCacheStoring: AnyObject {
    func loadSuggestions(forKey key: String) -> [SubstitutionSuggestion]?
    func save(_ suggestions: [SubstitutionSuggestion], forKey key: String)
}

/// File-backed cache: one JSON document in Application Support, the same
/// shape `OnlineRecipeCacheStore` uses for search results.
///
/// ## Why this outlives the process
///
/// `SubstitutionCache` on its own is per-instance and per-launch, and every
/// screen builds its own. On-device generation takes seconds, so the first
/// ask for an ingredient is slow *again* after a relaunch, and again on a
/// screen that happens to hold a different cache instance - which is most
/// visible exactly when it matters, demoing the feature. A shared file fixes
/// both: any instance reads what any other instance wrote, and a relaunch
/// starts warm.
///
/// Suggestions are derived data, not user data, so they stay on-device
/// rather than in Firestore. Read/write failures are treated as "no cache" -
/// a broken file costs a regeneration, never a failure.
nonisolated final class SubstitutionCacheStore: SubstitutionCacheStoring {
    /// Keeps the file from growing without bound. Each entry is at most
    /// three short suggestions, so this is generous for the usage pattern.
    private static let maxEntries = 60

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? FileManager.default.temporaryDirectory
            self.fileURL = base
                .appendingPathComponent("FridgeFit", isDirectory: true)
                .appendingPathComponent("substitution-cache.json", isDirectory: false)
        }
    }

    func loadSuggestions(forKey key: String) -> [SubstitutionSuggestion]? {
        loadAll().entries[key]
    }

    func save(_ suggestions: [SubstitutionSuggestion], forKey key: String) {
        var file = loadAll()
        file.entries[key] = suggestions
        file.order.removeAll { $0 == key }
        file.order.append(key)
        while file.order.count > Self.maxEntries {
            let evicted = file.order.removeFirst()
            file.entries[evicted] = nil
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(file).write(to: fileURL, options: .atomic)
        } catch {
            // Best effort: a failed write leaves the previous cache in place.
        }
    }

    private struct CacheFile: Codable {
        var entries: [String: [SubstitutionSuggestion]] = [:]
        /// Least-recently-saved first.
        var order: [String] = []
    }

    private func loadAll() -> CacheFile {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode(CacheFile.self, from: data)
        else { return CacheFile() }
        return decoded
    }
}

/// In-memory store for previews and tests - never touches the filesystem.
nonisolated final class InMemorySubstitutionCacheStore: SubstitutionCacheStoring {
    private(set) var stored: [String: [SubstitutionSuggestion]]

    init(initial: [String: [SubstitutionSuggestion]] = [:]) {
        self.stored = initial
    }

    func loadSuggestions(forKey key: String) -> [SubstitutionSuggestion]? { stored[key] }
    func save(_ suggestions: [SubstitutionSuggestion], forKey key: String) { stored[key] = suggestions }
}
