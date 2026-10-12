//
//  OnlineRecipePreferencesStore.swift
//  FridgeFit
//

import Foundation

/// Where the Discover tab's diet / intolerance / time filters are kept.
protocol OnlineRecipePreferencesStoring: AnyObject {
    func load() -> OnlineRecipePreferences
    func save(_ preferences: OnlineRecipePreferences)
}

/// `UserDefaults`-backed preferences. A corrupt or missing value falls back
/// to `.default` rather than failing.
final class UserDefaultsOnlineRecipePreferencesStore: OnlineRecipePreferencesStoring {
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
        return decoded
    }

    func save(_ preferences: OnlineRecipePreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}

/// In-memory preferences for previews and tests.
final class InMemoryOnlineRecipePreferencesStore: OnlineRecipePreferencesStoring {
    private(set) var preferences: OnlineRecipePreferences

    init(preferences: OnlineRecipePreferences = .default) {
        self.preferences = preferences
    }

    func load() -> OnlineRecipePreferences { preferences }
    func save(_ preferences: OnlineRecipePreferences) { self.preferences = preferences }
}
