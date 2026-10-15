//
//  StorageLocation.swift
//  FridgeFit
//

import Foundation

/// Where an item physically lives in the kitchen.
///
/// Optional on `PantryItem`: items added before this existed, and items
/// added by the receipt scanner or the camera, have no recorded location.
/// `PantryItem.storage` resolves that absence to `.pantry` for display
/// rather than inventing a fact about the user's fridge.
nonisolated enum StorageLocation: String, CaseIterable, Codable, Identifiable, Sendable {
    case fridge
    case freezer
    case pantry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fridge: return "Fridge"
        case .freezer: return "Freezer"
        case .pantry: return "Pantry"
        }
    }
}

/// Which storage area the kitchen screen is narrowed to.
///
/// Presentation state only - it filters what is shown and never changes a
/// stored item.
nonisolated enum InventoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case fridge
    case freezer
    case pantry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .fridge: return "Fridge"
        case .freezer: return "Freezer"
        case .pantry: return "Pantry"
        }
    }

    var storageLocation: StorageLocation? {
        switch self {
        case .all: return nil
        case .fridge: return .fridge
        case .freezer: return .freezer
        case .pantry: return .pantry
        }
    }
}

/// Whether "opened" means anything for an item.
///
/// A jar of sauce can be opened or unopened. Four loose tomatoes cannot, so
/// they use `.notApplicable` and the editor hides the control rather than
/// asking the user to maintain information that has no answer.
nonisolated enum OpenedState: String, Codable, Sendable {
    case unopened
    case opened
    case notApplicable
}
