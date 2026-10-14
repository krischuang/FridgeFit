import Foundation

/// Represents a food item currently stored in a household kitchen.
///
/// The item records how much food remains, where it is stored, whether expiry
/// tracking applies, and whether opening state is relevant.
///
/// Business Rules:
/// - A newly added inventory item must have a positive quantity.
/// - Remaining quantity must never become negative.
/// - Expiry tracking is optional.
/// - Foods where opening status is meaningless use `.notApplicable`.
public typealias InventoryItem = Ingredient

/// Represents the measurable or household-estimated amount of food available
/// for one inventory item.
///
/// Business Rules:
/// - Exact count and measured quantities cannot go below zero.
/// - Fractional measured quantities are supported.
/// - Display strings are presentation only; calculations use numeric values.
public typealias IngredientQuantity = Quantity

/// Describes a unit that can be attached to household food quantity.
///
/// The MVP keeps units explicit and avoids AI or package-to-weight conversion.
/// Packaging units such as bottles and jars are intentionally represented
/// separately from weight and volume units.
public enum FoodUnit: String, CaseIterable, Codable, Identifiable, Sendable {
    case piece
    case gram
    case kilogram
    case millilitre
    case litre
    case pack
    case bag
    case box
    case bottle
    case jar
    case can
    case tub
    case bunch
    case block
    case slice
    case loaf
    case stick

    public var id: String { rawValue }
}

/// Represents the household storage place for active food inventory.
///
/// Business Rule:
/// Every active inventory item must have one valid storage location.
public typealias FoodStorageLocation = StorageLocation

/// Represents whether opening state is meaningful for a food item.
///
/// Business Rule:
/// Items such as milk or jar sauce can be opened or unopened; loose foods such
/// as tomatoes use `.notApplicable` and should omit opening-state UI.
public typealias FoodOpenState = OpenedState

/// Represents the household food group assigned to an inventory item.
///
/// Food category is a domain classification used for browsing, searching, and
/// choosing a suitable display symbol. It does not infer nutrition or expiry
/// rules by itself; expiry and stock decisions must come from explicit item
/// data such as expiry date, storage location, and quantity.
///
/// Business Rules:
/// - Every inventory item belongs to one known household food category.
/// - Older persisted labels such as "Vegetables", "Meat", or "Grains" decode
///   into the closest current category so existing JSON remains readable.
/// - Unknown labels are preserved safely as `.other` instead of failing load.
public enum FoodCategory: String, CaseIterable, Codable, Identifiable, Sendable, ExpressibleByStringLiteral {
    case vegetables
    case fruit
    case dairy
    case meatAndFish
    case bakery
    case pantry
    case frozen
    case beverage
    case preparedMeal
    case snack
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vegetables: "Vegetables"
        case .fruit: "Fruit"
        case .dairy: "Dairy"
        case .meatAndFish: "Meat & Fish"
        case .bakery: "Bakery"
        case .pantry: "Pantry"
        case .frozen: "Frozen"
        case .beverage: "Beverage"
        case .preparedMeal: "Prepared Meal"
        case .snack: "Snack"
        case .other: "Other"
        }
    }

    public init(named name: String) {
        let normalized = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "/", with: "")

        switch normalized {
        case "vegetable", "vegetables", "veg":
            self = .vegetables
        case "fruit", "fruits":
            self = .fruit
        case "dairy", "dairyalternative":
            self = .dairy
        case "meat", "fish", "meatfish", "meatandfish", "seafood":
            self = .meatAndFish
        case "bakery", "bread", "bakedgoods":
            self = .bakery
        case "pantry", "grain", "grains", "staple", "staples":
            self = .pantry
        case "frozen", "freezer":
            self = .frozen
        case "beverage", "beverages", "drink", "drinks":
            self = .beverage
        case "preparedmeal", "preparedmeals", "leftovers":
            self = .preparedMeal
        case "snack", "snacks":
            self = .snack
        default:
            self = .other
        }
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(named: value)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self.init(named: value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(displayName)
    }
}

/// Represents derived expiry meaning for an inventory item.
///
/// Expiry status is calculated from the expiry date and current day. It is not
/// persisted because urgency changes as time passes.
public typealias ExpiryStatus = ExpiryState

/// Represents a meaningful committed household inventory event.
///
/// Activity is created only for saved operations such as added, used,
/// quantity-adjusted, finished, discarded, or edited. Draft edits and UI taps
/// are not inventory activity.
public typealias InventoryActivity = InventoryEvent

/// Represents why physical food leaves active household inventory.
///
/// Finished means the household used the food completely. Discarded means the
/// food was thrown away. Delete Record is intentionally not a food outcome
/// because it corrects data rather than describing food waste or consumption.
public enum FoodOutcome: Codable, Equatable, Sendable {
    case finished
    case discarded

    var eventKind: InventoryEventKind {
        switch self {
        case .finished: .finished
        case .discarded: .discarded
        }
    }

    var status: InventoryStatus {
        switch self {
        case .finished: .finished
        case .discarded: .discarded
        }
    }
}
