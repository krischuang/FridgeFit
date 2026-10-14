import Foundation

/// Represents where food is physically stored in the household.
///
/// Storage location helps the user find food quickly and supports kitchen
/// filtering across the fridge, freezer, and pantry.
public enum StorageLocation: String, CaseIterable, Codable, Identifiable, Sendable {
    case fridge
    case freezer
    case pantry

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fridge: "Fridge"
        case .freezer: "Freezer"
        case .pantry: "Pantry"
        }
    }
}

/// Represents the current storage filter applied to active kitchen inventory.
///
/// Filtering is presentation state for the household workflow: it narrows the
/// workspace to a physical storage area without changing the underlying
/// inventory records.
public enum InventoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case fridge
    case freezer
    case pantry

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All"
        case .fridge: "Fridge"
        case .freezer: "Freezer"
        case .pantry: "Pantry"
        }
    }

    public var storageLocation: StorageLocation? {
        switch self {
        case .all: nil
        case .fridge: .fridge
        case .freezer: .freezer
        case .pantry: .pantry
        }
    }
}
