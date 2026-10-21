import Foundation

nonisolated enum MeasurementSystemPreference: String, Codable, CaseIterable, Sendable {
    case metric
    case imperial

    var title: String {
        switch self {
        case .metric: return "Metric (g, ml, kg)"
        case .imperial: return "Imperial (oz, cups, lb)"
        }
    }
}

/// Profile preferences that are safe to persist locally today.
///
/// These values are explicitly presentation defaults. They do not rewrite
/// stored inventory quantities or alter recipe ingredient amounts.
nonisolated struct ProfileSettings: Codable, Equatable, Sendable {
    var measurementSystem: MeasurementSystemPreference = .metric
    var defaultServingSize: Int = 2

    mutating func setServingSize(_ value: Int) {
        defaultServingSize = min(max(value, 1), 12)
    }
}

nonisolated protocol ProfileSettingsStoring: Sendable {
    func load() -> ProfileSettings
    func save(_ settings: ProfileSettings)
}

nonisolated final class UserDefaultsProfileSettingsStore: ProfileSettingsStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "profileSettings") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> ProfileSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(ProfileSettings.self, from: data)
        else {
            return ProfileSettings()
        }
        return settings
    }

    func save(_ settings: ProfileSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
