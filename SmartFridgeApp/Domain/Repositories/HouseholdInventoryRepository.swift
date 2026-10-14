import Foundation

/// Describes persistence operations for household food inventory.
///
/// Use cases depend on this protocol instead of concrete persistence. The app
/// can store inventory with JSON today and change storage technology later
/// without changing business rules.
@MainActor
public protocol HouseholdInventoryRepository: AnyObject {
    var inventoryItems: [InventoryItem] { get }
    var inventoryActivities: [InventoryActivity] { get }

    func activeInventoryItems() -> [InventoryItem]
    func inventoryItem(id: UUID) -> InventoryItem?
    func saveInventoryItem(_ item: InventoryItem, activity: InventoryEventKind, note: String?, message: String?) throws
    func saveInventoryItem(_ item: InventoryItem, activities: [InventoryActivityChange], message: String?) throws
    func removeFromActiveInventory(_ item: InventoryItem, outcome: FoodOutcome) throws
    func deleteInventoryRecord(id: UUID) throws
    func activities(for itemID: UUID) -> [InventoryActivity]
}

public struct InventoryActivityChange: Equatable, Sendable {
    public var kind: InventoryEventKind
    public var note: String?

    public init(kind: InventoryEventKind, note: String? = nil) {
        self.kind = kind
        self.note = note
    }
}
