//
//  OnlineRecipePreferencesStore.swift
//  FridgeFit
//

import Foundation

/// Where the Discover tab's diet / intolerance / time filters are kept.
///
/// Implementations must return `OnlineRecipePreferences.sanitized()` from
/// `load()`, so a value stored by an earlier build can never reinstate an
/// intolerance filter FridgeFit does not actually perform. See
/// `OnlineRecipePreferences.sanitized()` for why that matters.
nonisolated protocol OnlineRecipePreferencesStoring: AnyObject {
    func load() -> OnlineRecipePreferences
    func save(_ preferences: OnlineRecipePreferences)
}

/// `UserDefaults`-backed preferences. A corrupt or missing value falls back
/// to `.default` rather than failing.
nonisolated final class UserDefaultsOnlineRecipePreferencesStore: OnlineRecipePreferencesStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "onlineRecipePreferences") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> OnlineRecipePreferences {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(OnlineRecipePreferences.self, from: data)
        else { return .default }
        return decoded.sanitized()
    }

    func save(_ preferences: OnlineRecipePreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}

/// In-memory preferences for previews and tests.
nonisolated final class InMemoryOnlineRecipePreferencesStore: OnlineRecipePreferencesStoring {
    private(set) var preferences: OnlineRecipePreferences

    init(preferences: OnlineRecipePreferences = .default) {
        self.preferences = preferences
    }

    func load() -> OnlineRecipePreferences { preferences.sanitized() }
    func save(_ preferences: OnlineRecipePreferences) { self.preferences = preferences }
}
