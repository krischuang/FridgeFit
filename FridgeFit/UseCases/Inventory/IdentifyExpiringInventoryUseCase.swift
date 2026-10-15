//
//  IdentifyExpiringInventoryUseCase.swift
//  FridgeFit
//

import Foundation

/// Picks out the food that should be used first because it is about to go
/// off, and orders the kitchen list.
///
/// **Rule:** include food that is expired, expires today, expires tomorrow,
/// or expires within three days. Exclude anything further out, and exclude
/// anything with no expiry date - an item nobody dated is not urgent, it is
/// simply untracked.
///
/// Pure and synchronous, operating on an array the caller already has rather
/// than reaching for a repository, so the whole policy is testable with no
/// storage and no clock.
nonisolated struct IdentifyExpiringInventoryUseCase {
    private let now: Date
    private let calendar: Calendar

    init(now: Date = .now, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    /// The "Use First" items, most urgent first.
    func execute(items: [PantryItem], searchText: String = "", filter: InventoryFilter = .all) -> [PantryItem] {
        matching(items: items, searchText: searchText, filter: filter)
            .filter { state(for: $0)?.shouldPrioritise == true }
            .sorted(by: urgencyThenName)
    }

    /// Everything else that matches the search and filter, so the two
    /// sections together are exactly the matching set with no item in both
    /// and none dropped.
    func remainder(items: [PantryItem], searchText: String = "", filter: InventoryFilter = .all) -> [PantryItem] {
        let urgentIDs = Set(execute(items: items, searchText: searchText, filter: filter).map(\.id))
        return matching(items: items, searchText: searchText, filter: filter)
            .filter { !urgentIDs.contains($0.id) }
            .sorted(by: urgencyThenName)
    }

    /// Search and storage filtering, shared by both sections.
    ///
    /// Category is searchable as well as name, so "dairy" finds the milk
    /// without the user remembering what they called it.
    func matching(items: [PantryItem], searchText: String, filter: InventoryFilter) -> [PantryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            let matchesStorage = filter.storageLocation == nil || item.storage == filter.storageLocation
            let matchesSearch = query.isEmpty
                || item.name.localizedCaseInsensitiveContains(query)
                || item.ingredient.category.displayName.localizedCaseInsensitiveContains(query)
            return matchesStorage && matchesSearch
        }
    }

    private func state(for item: PantryItem) -> ExpiryState? {
        ExpiryService.state(for: item.expiryDate, now: now, calendar: calendar)
    }

    /// Soonest expiry first, then alphabetical. Undated items sort last
    /// rather than first - `Int.max` days away is the honest reading of "we
    /// were never told when this goes off".
    private func urgencyThenName(_ lhs: PantryItem, _ rhs: PantryItem) -> Bool {
        let left = state(for: lhs)?.daysUntilExpiry ?? Int.max
        let right = state(for: rhs)?.daysUntilExpiry ?? Int.max
        if left != right { return left < right }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
