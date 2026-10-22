//
//  Identifiers.swift
//  FridgeFit
//

import Foundation

// A pantry item's identifier, as assigned by the Smart Fridge module.
nonisolated struct PantryItemID: Hashable, Codable, Sendable {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
}
