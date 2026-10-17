//
//  InMemoryPantryRepository.swift
//  FridgeFit
//

import Foundation

/// In-memory implementation of `PantryRepository`, used for SwiftUI
/// previews and as the test double for use case / view model unit tests.
/// Nothing persists between launches.
nonisolated final class InMemoryPantryRepository: PantryRepository {
    private var items: [PantryItem]

    init(seedItems: [PantryItem] = []) {
        self.items = seedItems
    }

    func fetchAll() async throws -> [PantryItem] {
        items
    }

    func fetch(id: UUID) async throws -> PantryItem? {
        items.first { $0.id == id }
    }

    /// Matches the rule the other two backends implement: undated items are
    /// excluded, and the result is soonest-first then alphabetical.
    func fetchExpiring(before date: Date) async throws -> [PantryItem] {
        items
            .filter { item in
                guard let expiryDate = item.expiryDate else { return false }
                return expiryDate <= date
            }
            .sorted { lhs, rhs in
                guard let left = lhs.expiryDate, let right = rhs.expiryDate else { return false }
                if left != right { return left < right }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func add(_ item: PantryItem) async throws {
        items.append(item)
    }

    func update(_ item: PantryItem) async throws {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            throw UpdatePantryItemError.itemNotFound
        }
        items[index] = item
    }

    func remove(id: UUID) async throws {
        guard items.contains(where: { $0.id == id }) else {
            throw RemovePantryItemError.pantryItemNotFound
        }
        items.removeAll { $0.id == id }
    }
}
