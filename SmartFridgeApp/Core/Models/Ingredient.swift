import Foundation

/// Describes whether a household food record is still part of active kitchen stock.
///
/// Finished and discarded food should no longer appear in active inventory, but
/// their past activity can remain in history so the household can understand
/// what happened to the item.
public enum InventoryStatus: String, Codable, Sendable {
    case available
    case finished
    case discarded
}

/// Represents whether opening state is meaningful for a tracked food item.
///
/// Packaged foods such as milk or jar sauce can be unopened or opened. Loose or
/// staple foods where that distinction is not useful use `notApplicable` so the
/// app does not ask the household to maintain meaningless information.
public enum OpenedState: String, Codable, Sendable {
    case unopened
    case opened
    case notApplicable
}

/// Represents food currently tracked by a household kitchen.
///
/// The record captures the household's understanding of the item: what it is,
/// where it is stored, how much remains, whether expiry tracking applies, and
/// whether opening state matters. Only `available` items belong in active
/// inventory; finished or discarded items can still be retained through activity
/// history.
public struct Ingredient: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var category: FoodCategory
    public var storageLocation: StorageLocation
    public var quantity: Quantity
    public var expiryDate: Date?
    public var openedState: OpenedState
    public var dateAdded: Date
    public var lastUpdated: Date
    public var lowStockThreshold: Double?
    public var status: InventoryStatus

    public init(
        id: UUID = UUID(),
        name: String,
        category: FoodCategory,
        storageLocation: StorageLocation,
        quantity: Quantity,
        expiryDate: Date? = nil,
        openedState: OpenedState = .notApplicable,
        dateAdded: Date = .now,
        lastUpdated: Date = .now,
        lowStockThreshold: Double? = nil,
        status: InventoryStatus = .available
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.storageLocation = storageLocation
        self.quantity = quantity
        self.expiryDate = expiryDate
        self.openedState = openedState
        self.dateAdded = dateAdded
        self.lastUpdated = lastUpdated
        self.lowStockThreshold = lowStockThreshold
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case storageLocation
        case quantity
        case expiryDate
        case openedState
        case dateAdded
        case lastUpdated
        case lowStockThreshold
        case status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decode(FoodCategory.self, forKey: .category)
        storageLocation = try container.decode(StorageLocation.self, forKey: .storageLocation)
        quantity = try container.decode(Quantity.self, forKey: .quantity)
        expiryDate = try container.decodeIfPresent(Date.self, forKey: .expiryDate)
        openedState = try container.decodeIfPresent(OpenedState.self, forKey: .openedState) ?? .notApplicable
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        lowStockThreshold = try container.decodeIfPresent(Double.self, forKey: .lowStockThreshold)
        status = try container.decode(InventoryStatus.self, forKey: .status)
    }

    /// Indicates whether the food should appear in the household's current kitchen.
    ///
    /// Finished and discarded records are intentionally excluded from active
    /// inventory while remaining available to history and audit-style views.
    public var isActive: Bool {
        status == .available
    }

    public var quantityType: QuantityType {
        quantity.type
    }

    public var quantityPrecision: QuantityPrecision {
        quantity.precision
    }

    /// Indicates whether the remaining amount has reached the household's low-stock threshold.
    ///
    /// Exact quantities use their configured threshold. Presence-based staples
    /// are considered low only when the household has explicitly marked them low.
    public var isLowStock: Bool {
        guard let threshold = lowStockThreshold, let amount = quantity.normalizedAmount else {
            if case .presence(.low) = quantity { return true }
            return false
        }
        return amount <= threshold
    }
}

/// Represents a reusable household food starting point for quick add flows.
///
/// Templates are seed/common-pick data rather than committed inventory. They
/// suggest a typical category, storage location, quantity, and optional expiry
/// offset before the user confirms a real inventory item.
public struct IngredientTemplate: Identifiable, Equatable, Sendable {
    public var id: String { name.lowercased() }
    public var name: String
    public var category: FoodCategory
    public var storageLocation: StorageLocation
    public var defaultQuantity: Quantity
    public var openedState: OpenedState
    public var lowStockThreshold: Double?
    public var expiryOffsetDays: Int?

    public init(
        name: String,
        category: FoodCategory,
        storageLocation: StorageLocation,
        defaultQuantity: Quantity,
        openedState: OpenedState = .notApplicable,
        lowStockThreshold: Double? = nil,
        expiryOffsetDays: Int? = nil
    ) {
        self.name = name
        self.category = category
        self.storageLocation = storageLocation
        self.defaultQuantity = defaultQuantity
        self.openedState = openedState
        self.lowStockThreshold = lowStockThreshold
        self.expiryOffsetDays = expiryOffsetDays
    }
}
