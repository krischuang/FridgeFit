//
//  FridgeFitPantryReading.swift
//  FridgeFit
//

import Foundation

// the bridge between the two modules. FridgeFunds wants a sync, read-only
// PantryReading; FridgeFit's pantry is an async PantryRepository (Firestore).
// so we grab a copy of the pantry in refresh() and answer reads from that copy,
// filling in price/expiry from the ItemPriceStore every time it's asked - which
// means editing a price shows up straight away without refetching anything.
final class FridgeFitPantryReading: PantryReading {
    private let repository: PantryRepository
    private let priceStore: ItemPriceStore
    private var cached: [PantryItem] = []

    init(repository: PantryRepository, priceStore: ItemPriceStore) {
        self.repository = repository
        self.priceStore = priceStore
    }

    func refresh() async throws {
        cached = try await repository.fetchAll()
    }

    func allItems() -> [PantryItemSnapshot] {
        cached.map(snapshot(of:))
    }

    func item(withID id: PantryItemID) -> PantryItemSnapshot? {
        cached.first { Self.id(for: $0) == id }.map(snapshot(of:))
    }

    static func id(for item: PantryItem) -> PantryItemID {
        PantryItemID(item.id.uuidString)
    }

    private func snapshot(of item: PantryItem) -> PantryItemSnapshot {
        let id = Self.id(for: item)
        let info = priceStore.info(for: id)
        return PantryItemSnapshot(
            id: id,
            name: item.name,
            quantity: item.quantity,
            unit: item.unit.symbol,
            // the pantry owns expiry now (Kitchen tab edits it). ours is only a
            // fallback for prices saved before that existed
            expiryDate: item.expiryDate ?? info?.expiryDate,
            unitCost: info?.unitCost
        )
    }
}
