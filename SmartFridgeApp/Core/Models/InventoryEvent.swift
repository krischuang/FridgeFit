import Foundation

/// Describes the real-world household action recorded in inventory history.
///
/// These cases are semantically distinct: using food is different from correcting
/// quantity, opening a package, finishing food, discarding food, editing details,
/// or deleting an incorrect record.
public enum InventoryEventKind: String, Codable, Sendable {
    case added
    case used
    case quantityAdjusted
    case opened
    case finished
    case discarded
    case deleted
    case edited
}

/// Represents a meaningful committed household inventory activity.
///
/// Activity history describes what the household did with food, not persistence
/// mechanics. Draft edits and transient UI interactions should not create events;
/// only saved operations such as added, used, opened, quantity-adjusted, finished,
/// discarded, deleted, or edited should appear here.
public struct InventoryEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var ingredientID: UUID
    public var ingredientName: String
    public var kind: InventoryEventKind
    public var note: String?
    public var date: Date

    public init(
        id: UUID = UUID(),
        ingredientID: UUID,
        ingredientName: String,
        kind: InventoryEventKind,
        note: String? = nil,
        date: Date = .now
    ) {
        self.id = id
        self.ingredientID = ingredientID
        self.ingredientName = ingredientName
        self.kind = kind
        self.note = note
        self.date = date
    }
}
