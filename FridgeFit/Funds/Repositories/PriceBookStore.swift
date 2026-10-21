//
//  PriceBookStore.swift
//  FridgeFit
//

import Foundation

// where the price book lives. same shape as the other FridgeFunds stores: sync,
// storage hidden behind a protocol, one version per backend.
protocol PriceBookStore: AnyObject {
    func entry(forIngredientNamed name: String) -> PriceBookEntry?
    // replaces whatever was there for that name - latest price wins
    func record(_ entry: PriceBookEntry)
}

nonisolated final class InMemoryPriceBookStore: PriceBookStore {
    private var byKey: [String: PriceBookEntry]

    init(_ entries: [PriceBookEntry] = []) {
        byKey = Dictionary(entries.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
    }

    func entry(forIngredientNamed name: String) -> PriceBookEntry? {
        byKey[PriceBookEntry.key(for: name)]
    }

    func record(_ entry: PriceBookEntry) {
        byKey[entry.key] = entry
    }
}
