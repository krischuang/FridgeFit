import Foundation
import Observation

enum IngredientDrawerSaveResult: Equatable {
    case saved
    case removed(UUID)
    case unchanged
}

/// Coordinates the Ingredient Drawer presentation state and inventory actions.
///
/// The drawer is intentionally contextual: My Kitchen remains visible behind it,
/// while this ViewModel owns the local edit draft, used amount input, validation
/// feedback, and save intents. It delegates committed business operations to
/// use cases so the SwiftUI view does not calculate inventory outcomes or write
/// persistence directly.
@MainActor
@Observable
final class IngredientDrawerViewModel {
    private let itemID: UUID

    @ObservationIgnored private let repository: any HouseholdInventoryRepository
    @ObservationIgnored private let recordIngredientUse: RecordIngredientUseUseCase
    @ObservationIgnored private let updateInventoryItemDetails: UpdateInventoryItemDetailsUseCase
    @ObservationIgnored private let recordFoodOutcome: RecordFoodOutcomeUseCase

    var draft: IngredientDraft?
    var usedAmountText = "0"
    var usedAmountInputIsValid = true
    var errorMessage: String?

    init(itemID: UUID, repository: any HouseholdInventoryRepository) {
        self.itemID = itemID
        self.repository = repository
        recordIngredientUse = RecordIngredientUseUseCase(repository: repository)
        updateInventoryItemDetails = UpdateInventoryItemDetailsUseCase(repository: repository)
        recordFoodOutcome = RecordFoodOutcomeUseCase(repository: repository)
    }

    var visibleIngredient: InventoryItem? {
        draft?.previewIngredient ?? repository.inventoryItem(id: itemID)
    }

    var recentActivity: [InventoryActivity] {
        Array(repository.activities(for: itemID).prefix(3))
    }

    func load() {
        guard draft == nil, let item = repository.inventoryItem(id: itemID) else { return }
        draft = IngredientDraft(original: item)
        usedAmountText = "0"
        usedAmountInputIsValid = true
        errorMessage = nil
    }

    func updateDraft(_ changes: (inout IngredientDraft) -> Void) {
        guard var next = draft else { return }
        changes(&next)
        draft = next
    }

    func markOpened() {
        updateDraft { $0.openedState = .opened }
    }

    func toggleFinished() {
        updateDraft { $0.toggleFinished() }
        syncUsedAmountText()
    }

    func changeUsedAmount(by delta: Double) {
        updateDraft { $0.setUsedAmount($0.usedAmount + delta, clampedToAvailable: true) }
        syncUsedAmountText()
        usedAmountInputIsValid = true
        errorMessage = nil
    }

    func applyTypedUsedAmount(updateText: Bool) {
        let cleaned = usedAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty || Double(cleaned) != nil else {
            usedAmountInputIsValid = false
            return
        }

        usedAmountInputIsValid = true
        errorMessage = nil
        let parsed = Double(cleaned) ?? 0
        guard let draft else { return }
        guard parsed <= draft.maxAmount else {
            usedAmountInputIsValid = false
            errorMessage = draft.amountExceedsAvailableMessage
            return
        }

        updateDraft { $0.setUsedAmount(parsed, clampedToAvailable: false) }
        if updateText {
            syncUsedAmountText()
        }
    }

    func syncUsedAmountText() {
        guard let draft else { return }
        usedAmountText = UsedAmountFormatter.inputString(amount: draft.usedAmount, quantity: draft.baseQuantity)
        usedAmountInputIsValid = true
    }

    func save() -> IngredientDrawerSaveResult {
        guard usedAmountInputIsValid else { return .unchanged }
        guard let draft, draft.canSave else { return .unchanged }

        do {
            if draft.finished {
                try recordFoodOutcome.execute(item: draft.finalIngredient, outcome: .finished)
                return .removed(draft.original.id)
            }

            if draft.usedAmount > 0, !draft.hasDetailChanges, !draft.quantityWasCorrected {
                try recordIngredientUse.execute(itemID: draft.original.id, usedAmount: draft.usedAmount)
                return .saved
            }

            if draft.usedAmount > 0 {
                let details = try updateInventoryItemDetails.validate(draft.detailsUpdateRequest)
                let finalItem = try recordIngredientUse.validate(item: details.item, usedAmount: draft.usedAmount)
                let usedNote = "Used \(QuantityFormatter.number(draft.usedAmount))"
                try repository.saveInventoryItem(
                    finalItem,
                    activities: [
                        InventoryActivityChange(kind: details.activity),
                        InventoryActivityChange(kind: .used, note: usedNote)
                    ],
                    message: usedNote
                )
                return .saved
            }

            try updateInventoryItemDetails.execute(draft.detailsUpdateRequest)
            return .saved
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
            return .unchanged
        } catch {
            errorMessage = "Your kitchen could not be updated right now. Try again."
            return .unchanged
        }
    }

    func discard() -> IngredientDrawerSaveResult {
        guard let draft else { return .unchanged }

        do {
            try recordFoodOutcome.execute(itemID: draft.original.id, outcome: .discarded)
            return .removed(draft.original.id)
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
            return .unchanged
        } catch {
            errorMessage = "Your kitchen could not be updated right now. Try again."
            return .unchanged
        }
    }

    func deleteRecord() -> IngredientDrawerSaveResult {
        do {
            try repository.deleteInventoryRecord(id: itemID)
            return .removed(itemID)
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
            return .unchanged
        } catch {
            errorMessage = "This record could not be deleted right now. Try again."
            return .unchanged
        }
    }
}

/// Represents unsaved changes made inside the Ingredient Drawer.
///
/// Business Rules:
/// - Draft changes do not alter repository state until Save is requested.
/// - Used amount is a final value, not a cumulative sequence of typed edits.
/// - Remaining quantity cannot become negative.
/// - Finished means the item leaves active inventory as a food outcome.
struct IngredientDraft: Equatable {
    let original: InventoryItem
    var name: String
    var category: FoodCategory
    var storageLocation: FoodStorageLocation
    var baseQuantity: IngredientQuantity
    var expiryDate: Date?
    var openedState: FoodOpenState
    var lowStockThreshold: Double?
    var usedAmount = 0.0
    var finished = false
    var preFinishedUsedAmount = 0.0
    var quantityWasCorrected = false

    init(original: InventoryItem) {
        self.original = original
        name = original.name
        category = original.category
        storageLocation = original.storageLocation
        baseQuantity = original.quantity
        expiryDate = original.expiryDate
        openedState = original.openedState
        lowStockThreshold = original.lowStockThreshold
    }

    var previewIngredient: InventoryItem {
        var item = original
        item.name = name
        item.category = category
        item.storageLocation = storageLocation
        item.quantity = baseQuantity
        item.expiryDate = expiryDate
        item.openedState = openedState
        item.lowStockThreshold = lowStockThreshold
        return item
    }

    var finalIngredient: InventoryItem {
        var item = previewIngredient
        item.quantity = finished ? zeroQuantity(from: baseQuantity) : remainingQuantity
        item.status = finished ? .finished : original.status
        return item
    }

    var detailsUpdateRequest: UpdateInventoryItemDetailsRequest {
        UpdateInventoryItemDetailsRequest(
            itemID: original.id,
            name: name,
            category: category,
            storageLocation: storageLocation,
            quantity: baseQuantity,
            expiryDate: expiryDate,
            openState: openedState,
            lowStockThreshold: lowStockThreshold,
            quantityWasCorrected: quantityWasCorrected
        )
    }

    var remainingQuantity: IngredientQuantity {
        quantityAfterUsing(amount: usedAmount, from: baseQuantity)
    }

    var canSave: Bool {
        hasChanges && isValid
    }

    var hasChanges: Bool {
        finished || usedAmount > 0 || hasDetailChanges || quantityWasCorrected
    }

    var hasDetailChanges: Bool {
        name != original.name
            || category != original.category
            || storageLocation != original.storageLocation
            || expiryDate != original.expiryDate
            || openedState != original.openedState
            || lowStockThreshold != original.lowStockThreshold
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && usedAmount >= 0
            && usedAmount <= maxAmount
    }

    var maxAmount: Double {
        baseQuantity.normalizedAmount ?? 1
    }

    var amountExceedsAvailableMessage: String {
        let available = UsedAmountFormatter.display(amount: maxAmount, quantity: baseQuantity)
        return "Only \(available) of \(name) is available. Enter an amount up to \(available)."
    }

    mutating func setUsedAmount(_ amount: Double, clampedToAvailable: Bool) {
        let normalized = max(normalizedUsedAmount(amount, for: baseQuantity), 0)
        usedAmount = clampedToAvailable ? min(normalized, maxAmount) : normalized
        if usedAmount >= maxAmount, maxAmount > 0 {
            finished = true
        } else if finished {
            finished = false
        }
    }

    mutating func toggleFinished() {
        if finished {
            finished = false
            setUsedAmount(preFinishedUsedAmount, clampedToAvailable: true)
        } else {
            preFinishedUsedAmount = usedAmount
            setUsedAmount(maxAmount, clampedToAvailable: true)
            finished = true
        }
    }

    mutating func clampUsedAmount() {
        if finished {
            usedAmount = maxAmount
        } else {
            usedAmount = min(max(usedAmount, 0), maxAmount)
            if usedAmount >= maxAmount, maxAmount > 0 {
                finished = true
            }
        }
    }

    private func normalizedUsedAmount(_ amount: Double, for quantity: IngredientQuantity) -> Double {
        switch quantity {
        case .count:
            return amount.rounded()
        case .presence:
            return amount >= 1 ? 1 : amount
        case .measure, .package:
            return amount
        }
    }

    private func quantityAfterUsing(amount: Double, from quantity: IngredientQuantity) -> IngredientQuantity {
        (try? quantity.subtracting(amount)) ?? quantity
    }

    private func zeroQuantity(from quantity: IngredientQuantity) -> IngredientQuantity {
        switch quantity {
        case .count(_, let unit):
            return .count(0, unit: unit)
        case .measure(_, let unit):
            return .measure(0, unit: unit)
        case .package(_, let unit, _):
            return .package(count: 0, unit: unit, level: .almostEmpty)
        case .presence:
            return .presence(.low)
        }
    }
}

enum UsedAmountFormatter {
    static func display(amount: Double, quantity: IngredientQuantity) -> String {
        switch quantity {
        case .count(_, let unit):
            return "\(Int(amount.rounded())) \(unit.rawValue)"
        case .measure(_, let unit):
            return "\(QuantityFormatter.number(amount)) \(unit.rawValue)"
        case .package(_, let unit, _):
            return "\(QuantityFormatter.number(amount)) \(unit.rawValue)\(amount > 1 ? "s" : "")"
        case .presence:
            return amount >= 1 ? "All" : "0"
        }
    }

    static func inputString(amount: Double, quantity: IngredientQuantity) -> String {
        switch quantity {
        case .count:
            return "\(Int(amount.rounded()))"
        default:
            return QuantityFormatter.number(amount)
        }
    }
}
