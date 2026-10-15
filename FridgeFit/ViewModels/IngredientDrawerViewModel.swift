//
//  IngredientDrawerViewModel.swift
//  FridgeFit
//

import Combine
import Foundation

/// What a drawer save did, so the presenting screen knows whether to close.
enum IngredientDrawerSaveResult: Equatable {
    case saved
    case removed(UUID)
    case unchanged
}

/// Drives the ingredient drawer.
///
/// The drawer is a contextual sheet - My Kitchen stays visible behind it -
/// and it edits a *draft*. Nothing reaches the pantry until Save, which is
/// what lets someone open it, drag the amount around to see what's left, and
/// close it again without having changed anything.
///
/// Business operations go to use cases through `InventoryStore`; this type
/// decides nothing about inventory itself.
@MainActor
final class IngredientDrawerViewModel: ObservableObject {
    private let itemID: UUID
    private let inventory: InventoryStore

    @Published var draft: IngredientDraft?
    @Published var usedAmountText = "0"
    @Published var usedAmountInputIsValid = true
    @Published var errorMessage: String?
    @Published private(set) var isSaving = false

    init(itemID: UUID, inventory: InventoryStore) {
        self.itemID = itemID
        self.inventory = inventory
    }

    /// What the drawer shows: the draft if one is open, otherwise the stored
    /// item. `nil` once the item is gone, which is how the sheet knows to
    /// close itself.
    var visibleItem: PantryItem? {
        draft?.previewItem ?? inventory.item(id: itemID)
    }

    /// The last few things that happened to this item.
    var recentActivity: [InventoryEvent] {
        Array(inventory.history(for: itemID).prefix(3))
    }

    func load() {
        guard draft == nil, let item = inventory.item(id: itemID) else { return }
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

    /// Validates what the user typed into the amount field.
    ///
    /// Refuses non-numbers and anything above what is actually there, and
    /// says so - rather than silently clamping, which looks like the app
    /// ignoring the keystroke.
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

    /// Commits the draft.
    ///
    /// Three outcomes, in priority order: finishing the item removes it;
    /// detail edits and a used amount are saved together as one undoable
    /// action; detail edits alone are just an update.
    func save() async -> IngredientDrawerSaveResult {
        guard usedAmountInputIsValid else { return .unchanged }
        guard let draft, draft.canSave else { return .unchanged }

        isSaving = true
        defer { isSaving = false }

        do {
            if draft.finished {
                try await inventory.record(outcome: .finished, for: draft.original.id)
                return .removed(draft.original.id)
            }

            try await inventory.saveDrawerChanges(
                details: draft.detailsUpdateRequest,
                includeDetails: draft.hasDetailChanges || draft.quantityWasCorrected,
                usedAmount: draft.usedAmount
            )
            return .saved
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
            return .unchanged
        } catch {
            errorMessage = "Your kitchen could not be updated right now. Try again."
            return .unchanged
        }
    }

    /// Records the food as thrown away. Distinct from finishing it, and from
    /// deleting the record - see `FoodOutcome`.
    func discard() async -> IngredientDrawerSaveResult {
        await remove { try await self.inventory.record(outcome: .discarded, for: self.itemID) }
    }

    /// Removes a row that was wrong, without claiming anything about the
    /// food.
    func deleteRecord() async -> IngredientDrawerSaveResult {
        await remove { try await self.inventory.deleteRecord(for: self.itemID) }
    }

    private func remove(_ operation: () async throws -> Void) async -> IngredientDrawerSaveResult {
        isSaving = true
        defer { isSaving = false }
        do {
            try await operation()
            return .removed(itemID)
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
            return .unchanged
        } catch {
            errorMessage = "Your kitchen could not be updated right now. Try again."
            return .unchanged
        }
    }
}

/// Unsaved changes inside the drawer.
///
/// **Rules:** nothing here touches storage until Save. The used amount is a
/// final value rather than a running total of taps, the remainder can never
/// go negative, and using everything is the same as finishing it - which is
/// why `setUsedAmount` flips `finished` when the amount reaches the maximum.
struct IngredientDraft: Equatable {
    let original: PantryItem
    var name: String
    var category: IngredientCategory
    var storageLocation: StorageLocation
    var baseQuantity: Quantity
    var expiryDate: Date?
    var openedState: OpenedState
    var lowStockThreshold: Double?
    var usedAmount = 0.0
    var finished = false
    /// What the used amount was before "finished" was toggled on, so
    /// toggling it back off restores it instead of resetting to zero.
    var preFinishedUsedAmount = 0.0
    var quantityWasCorrected = false

    init(original: PantryItem) {
        self.original = original
        name = original.name
        category = original.ingredient.category
        storageLocation = original.storage
        baseQuantity = original.inventoryQuantity
        expiryDate = original.expiryDate
        openedState = original.opened
        lowStockThreshold = original.lowStockThreshold
    }

    /// The item as the drawer currently shows it - draft fields applied, but
    /// not the pending use, so the header keeps showing what is there while
    /// the amount control shows what would be taken.
    var previewItem: PantryItem {
        var item = original
        item.ingredient.name = name
        item.ingredient.category = category
        item.storageLocation = storageLocation
        item.setInventoryQuantity(baseQuantity)
        item.expiryDate = expiryDate
        item.openedState = openedState
        item.lowStockThreshold = lowStockThreshold
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
            openedState: openedState,
            lowStockThreshold: lowStockThreshold,
            quantityWasCorrected: quantityWasCorrected
        )
    }

    /// What would be left after the pending use.
    var remainingQuantity: Quantity {
        (try? baseQuantity.subtracting(usedAmount)) ?? baseQuantity
    }

    var canSave: Bool { hasChanges && isValid }

    var hasChanges: Bool {
        finished || usedAmount > 0 || hasDetailChanges || quantityWasCorrected
    }

    var hasDetailChanges: Bool {
        name != original.name
            || category != original.ingredient.category
            || storageLocation != original.storage
            || expiryDate != original.expiryDate
            || openedState != original.opened
            || lowStockThreshold != original.lowStockThreshold
            || baseQuantity != original.inventoryQuantity
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && usedAmount >= 0
            && usedAmount <= maxAmount
    }

    var maxAmount: Double { baseQuantity.normalizedAmount }

    var amountExceedsAvailableMessage: String {
        let available = UsedAmountFormatter.display(amount: maxAmount, quantity: baseQuantity)
        return "Only \(available) of \(name) is available. Enter an amount up to \(available)."
    }

    mutating func setUsedAmount(_ amount: Double, clampedToAvailable: Bool) {
        let normalized = max(normalizedUsedAmount(amount, for: baseQuantity), 0)
        usedAmount = clampedToAvailable ? min(normalized, maxAmount) : normalized
        // Using all of something and finishing it are the same event, so the
        // two controls stay in step rather than letting the user save "used
        // 6 of 6 eggs, still in the fridge".
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

    /// Re-clamps the used amount after the base quantity was corrected.
    ///
    /// Needed because correcting "6 eggs" down to "2" while 4 are already
    /// marked used would otherwise leave a draft claiming more was used than
    /// exists - which `isValid` would reject with no way for the user to see
    /// why.
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

    /// Counts are whole things - half an egg is not a quantity anyone
    /// records - so typed and stepped amounts round. Weights and volumes
    /// keep their fraction.
    private func normalizedUsedAmount(_ amount: Double, for quantity: Quantity) -> Double {
        switch quantity {
        case .count:
            return amount.rounded()
        case .measure, .package:
            return amount
        }
    }
}

/// Formats the "how much did you use" field.
///
/// Separate from `QuantityFormatter` because this prints an *amount taken*
/// rather than an amount held: the unit comes from the item, the number from
/// the control, and a package reads "1 bottle" not "½ bottle".
enum UsedAmountFormatter {
    static func display(amount: Double, quantity: Quantity) -> String {
        switch quantity {
        case .count(_, let unit):
            return "\(Int(amount.rounded())) \(unit.symbol)"
        case .measure(_, let unit):
            return "\(QuantityFormatter.number(amount)) \(unit.symbol)"
        case .package(_, let unit, _):
            return "\(QuantityFormatter.number(amount)) \(unit.rawValue)\(amount > 1 ? "s" : "")"
        }
    }

    static func inputString(amount: Double, quantity: Quantity) -> String {
        switch quantity {
        case .count:
            return "\(Int(amount.rounded()))"
        case .measure, .package:
            return QuantityFormatter.number(amount)
        }
    }
}
