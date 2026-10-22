//
//  CountingPantryRepository.swift
//  FridgeFitTests
//

import Foundation
@testable import FridgeFit

/// `InMemoryPantryRepository` that records how many times the pantry was
/// read.
///
/// A local re-check costs no API quota, but it does cost a pantry read - and
/// a burst of edits, or a tab change landing together with the view's own
/// `onAppear`, used to pay for one each. These counts are how the coalescing
/// is asserted.
nonisolated final class CountingPantryRepository: PantryRepository {
    private(set) var fetchAllCount = 0
    private var items: [PantryItem]

    init(seedItems: [PantryItem] = []) {
        self.items = seedItems
    }

    func fetchAll() async throws -> [PantryItem] {
        fetchAllCount += 1
        return items
    }

    func fetch(id: UUID) async throws -> PantryItem? {
        items.first { $0.id == id }
    }

    func fetchExpiring(before date: Date) async throws -> [PantryItem] {
        items.filter { item in
            guard let expiryDate = item.expiryDate else { return false }
            return expiryDate <= date
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
