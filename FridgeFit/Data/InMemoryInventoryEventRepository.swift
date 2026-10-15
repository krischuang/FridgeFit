//
//  InMemoryInventoryEventRepository.swift
//  FridgeFit
//

import Foundation

/// In-memory `InventoryEventRepository` for previews and unit tests.
/// Nothing persists between launches.
final class InMemoryInventoryEventRepository: InventoryEventRepository {
    private var events: [InventoryEvent]

    init(seedEvents: [InventoryEvent] = []) {
        self.events = seedEvents
    }

    func fetchAll(limit: Int) async throws -> [InventoryEvent] {
        Array(events.sorted { $0.date > $1.date }.prefix(limit))
    }

    func append(_ event: InventoryEvent) async throws {
        events.append(event)
    }

    func remove(ids: [UUID]) async throws {
        let removing = Set(ids)
        events.removeAll { removing.contains($0.id) }
    }
}
