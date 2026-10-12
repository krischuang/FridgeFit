//
//  OnlineRecipeCacheStore.swift
//  FridgeFit
//

import Foundation

/// Stores the last successful online search per query key so it can be
/// served when offline. See `CachingOnlineRecipeService.cacheKey(for:)`.
protocol OnlineRecipeCacheStoring: AnyObject {
    func loadMatches(forKey key: String) -> [OnlineRecipeMatch]?
    func save(_ matches: [OnlineRecipeMatch], forKey key: String)
}

/// File-backed cache: one JSON document in Application Support. Recipe
/// search results aren't user data, so they stay on-device rather than in
/// Firestore. Read/write failures are treated as "no cache".
final class OnlineRecipeCacheStore: OnlineRecipeCacheStoring {
    /// Keeps the file from growing without bound.
    private static let maxEntries = 20

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
                .appendingPathComponent("online-recipe-cache.json", isDirectory: false)
        }
    }

    func loadMatches(forKey key: String) -> [OnlineRecipeMatch]? {
        loadAll().entries[key]
    }

    func save(_ matches: [OnlineRecipeMatch], forKey key: String) {
        var file = loadAll()
        file.entries[key] = matches
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
        var entries: [String: [OnlineRecipeMatch]] = [:]
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

/// In-memory cache for previews and tests - never touches the filesystem.
final class InMemoryOnlineRecipeCacheStore: OnlineRecipeCacheStoring {
    private(set) var stored: [String: [OnlineRecipeMatch]]

    init(initial: [String: [OnlineRecipeMatch]] = [:]) {
        self.stored = initial
    }

    func loadMatches(forKey key: String) -> [OnlineRecipeMatch]? { stored[key] }
    func save(_ matches: [OnlineRecipeMatch], forKey key: String) { stored[key] = matches }
}
