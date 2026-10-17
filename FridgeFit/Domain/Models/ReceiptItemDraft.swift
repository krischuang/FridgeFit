//
//  ReceiptItemDraft.swift
//  FridgeFit
//

import Foundation

/// An editable row on the receipt confirmation screen: what the scan found,
/// plus the corrections the user has made to it.
///
/// Sits between `ReceiptIngredientCandidate` (what the scan produced) and
/// `PantryItem` (what gets stored).
///
/// ## Quantity is not invented
///
/// When the receipt stated a quantity, that quantity and its unit are filled
/// in. When it did not, `quantityText` starts **empty** and the row reads
/// "quantity not detected" - the user supplies the number. The previous
/// fridge-scan flow defaulted every row to `1 pcs`, which silently put a
/// made-up quantity into the pantry whenever the user didn't notice. An
/// empty quantity is rejected by `AddDetectedIngredientsUseCase` with a
/// clear message, which is the correct outcome for a number nobody knows.
nonisolated struct ReceiptItemDraft: Identifiable, Equatable {
    let candidate: ReceiptIngredientCandidate
    /// Only ticked items are sent to the pantry.
    var isSelected: Bool
    var name: String
    var category: IngredientCategory
    /// Empty means the receipt didn't say and the user hasn't decided.
    var quantityText: String
    var unit: MeasurementUnit

    var id: UUID { candidate.id }
    var sourceText: String { candidate.sourceText }
    var isAlreadyInPantry: Bool { candidate.isAlreadyInPantry }
    /// Whether the receipt itself stated a quantity, so the row can say so
    /// rather than showing a blank box with no explanation.
    var hasDetectedQuantity: Bool { candidate.quantity != nil }

    /// Builds the default draft for a fresh candidate.
    ///
    /// Items already in the pantry start unticked - adding them would just
    /// be rejected by `AddPantryItemUseCase`'s duplicate rule.
    init(candidate: ReceiptIngredientCandidate) {
        self.candidate = candidate
        self.isSelected = !candidate.isAlreadyInPantry
        self.name = candidate.displayName
        self.category = candidate.category
        self.quantityText = candidate.quantity.map(Self.editableText(for:)) ?? ""
        // Falls back to pieces purely as the picker's starting position; with
        // an empty quantity nothing is stored until the user types a number.
        self.unit = candidate.quantity?.unit ?? .pieces
    }

    /// The quantity to store, or `nil` if the field is empty or unusable.
    /// `AddPantryItemUseCase` still has the final say.
    var quantity: Double? {
        let trimmed = quantityText.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value >= 0 else { return nil }
        return value
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Renders a detected quantity for a text field - whole numbers without
    /// a decimal point, so `500 g` doesn't become `500.0`.
    private static func editableText(for quantity: ReceiptQuantity) -> String {
        quantity.value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", quantity.value)
            : String(quantity.value)
    }
}
