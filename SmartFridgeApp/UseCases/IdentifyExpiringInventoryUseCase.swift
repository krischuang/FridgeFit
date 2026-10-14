import Foundation

public enum IdentifyExpiringInventoryError: LocalizedError, Equatable {
    case inventoryUnavailable

    public var errorDescription: String? {
        switch self {
        case .inventoryUnavailable:
            return "Your kitchen couldn’t be loaded right now. Try again."
        }
    }
}

/// Identifies active food that should be used first because expiry is close.
///
/// MVP Business Rule:
/// Include food that is expired, expires today, expires tomorrow, or expires
/// within the next three days. Exclude foods without expiry tracking and foods
/// beyond the Use First window. Results are sorted most urgent first.
///
/// Error Handling:
/// The current repository contract exposes already-loaded household inventory
/// synchronously, so normal expiry classification is deterministic and
/// non-throwing. `IdentifyExpiringInventoryError.inventoryUnavailable` is kept
/// as the domain-facing error for a future repository-loading boundary without
/// manufacturing an artificial failure in this pure classification path.
@MainActor
public struct IdentifyExpiringInventoryUseCase {
    private let repository: any HouseholdInventoryRepository
    private let now: Date
    private let calendar: Calendar

    public init(
        repository: any HouseholdInventoryRepository,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.now = now
        self.calendar = calendar
    }

    public func execute(searchText: String = "", filter: InventoryFilter = .all) -> [InventoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return repository.activeInventoryItems()
            .filter { item in
                let matchesStorage = filter.storageLocation == nil || item.storageLocation == filter.storageLocation
                let matchesSearch = query.isEmpty
                    || item.name.localizedCaseInsensitiveContains(query)
                    || item.category.displayName.localizedCaseInsensitiveContains(query)
                guard matchesStorage && matchesSearch else { return false }
                return ExpiryService.state(for: item.expiryDate, now: now, calendar: calendar)?.shouldPrioritise == true
            }
            .sorted { lhs, rhs in
                let left = ExpiryService.state(for: lhs.expiryDate, now: now, calendar: calendar)?.daysUntilExpiry ?? Int.max
                let right = ExpiryService.state(for: rhs.expiryDate, now: now, calendar: calendar)?.daysUntilExpiry ?? Int.max
                if left != right { return left < right }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
}
