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
