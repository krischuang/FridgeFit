//
//  HiddenOnlineRecipeStore.swift
//  FridgeFit
//

import Foundation

/// Provider recipe ids the user chose to hide on this device.
///
/// Kept in `UserDefaults` next to the Discover filters - a small set of
/// ids, not app data - so it doesn't depend on the persistence layer.
protocol HiddenOnlineRecipeStoring: AnyObject {
    func load() -> Set<Int>
    func save(_ ids: Set<Int>)
}

nonisolated final class UserDefaultsHiddenOnlineRecipeStore: HiddenOnlineRecipeStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "hiddenOnlineRecipeIDs") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> Set<Int> {
        Set((defaults.array(forKey: key) as? [Int]) ?? [])
    }

    func save(_ ids: Set<Int>) {
        defaults.set(ids.sorted(), forKey: key)
    }
}

/// In-memory store for previews and tests.
nonisolated final class InMemoryHiddenOnlineRecipeStore: HiddenOnlineRecipeStoring {
    private(set) var ids: Set<Int>

    init(ids: Set<Int> = []) {
        self.ids = ids
    }

    func load() -> Set<Int> { ids }
    func save(_ ids: Set<Int>) { self.ids = ids }
}
