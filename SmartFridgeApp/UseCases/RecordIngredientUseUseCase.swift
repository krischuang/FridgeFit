import Foundation

public enum RecordIngredientUseError: LocalizedError, Equatable {
    case itemNotFound
    case invalidUsedAmount
    case amountExceedsAvailable(available: Double, unit: String)
    case incompatibleUnit

    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "This food is no longer in your kitchen. Refresh your kitchen and try again."
        case .invalidUsedAmount:
            return "Enter an amount greater than zero before updating this food."
        case .amountExceedsAvailable(let available, let unit):
            return "Only \(QuantityFormatter.number(available)) \(unit) is available. Enter an amount up to \(QuantityFormatter.number(available)) \(unit)."
        case .incompatibleUnit:
            return "This food does not have a measurable amount. Correct the quantity before recording use."
        }
    }
}

/// Records a household using some of an ingredient and updates remaining stock.
///
/// Business Rules:
/// - Used amount must be greater than zero.
/// - Used amount cannot exceed the available amount.
/// - Remaining quantity must never become negative.
/// - Successful use creates exactly one meaningful `used` activity.
@MainActor
public struct RecordIngredientUseUseCase {
    private let repository: any HouseholdInventoryRepository

    public init(repository: any HouseholdInventoryRepository) {
        self.repository = repository
    }

    @discardableResult
    public func execute(itemID: UUID, usedAmount: Double) throws -> InventoryItem {
        guard let existingItem = repository.inventoryItem(id: itemID) else {
            throw RecordIngredientUseError.itemNotFound
        }
        let item = try validate(item: existingItem, usedAmount: usedAmount)

        let note = "Used \(QuantityFormatter.number(usedAmount))"
        try repository.saveInventoryItem(item, activity: .used, note: note, message: note)
        return item
    }

    @discardableResult
    public func validate(item: InventoryItem, usedAmount: Double) throws -> InventoryItem {
        guard item.isActive else {
            throw RecordIngredientUseError.itemNotFound
        }
        guard usedAmount > 0 else {
            throw RecordIngredientUseError.invalidUsedAmount
        }

        var updatedItem = item
        do {
            updatedItem.quantity = try item.quantity.subtracting(usedAmount)
        } catch IngredientQuantityError.amountExceedsAvailable(let available, let unit) {
            throw RecordIngredientUseError.amountExceedsAvailable(available: available, unit: unit)
        } catch IngredientQuantityError.incompatibleUnit {
            throw RecordIngredientUseError.incompatibleUnit
        } catch {
            throw RecordIngredientUseError.invalidUsedAmount
        }
        return updatedItem
    }
}
