//
//  DetectedIngredientDraft.swift
//  FridgeFit
//

import Foundation

/// An editable row on the ingredient review screen: what the scan detected,
/// plus the corrections the user has made to it.
///
/// Sits between `DetectedIngredient` (what the model produced) and
/// `PantryItem` (what gets stored). The original detection is kept
/// alongside the edits so the UI can still show the confidence the model
/// reported even after the user renames something.
struct DetectedIngredientDraft: Identifiable, Equatable {
    let detection: DetectedIngredient
    /// Only detections the user ticked are sent to the pantry.
    var isSelected: Bool
    var name: String
    var category: IngredientCategory
    var quantityText: String
    var unit: MeasurementUnit

    var id: UUID { detection.id }
    var confidence: ModelStatedConfidence { detection.confidence }
    var isAlreadyInPantry: Bool { detection.isAlreadyInPantry }

    /// Builds the default draft for a fresh detection.
    ///
    /// Detections already in the pantry start unticked - adding them would
    /// just be rejected by `AddPantryItemUseCase`'s duplicate rule.
    /// Quantity defaults to the count the model saw, or `1 pcs` when it
    /// couldn't tell, rather than inventing a weight.
    init(detection: DetectedIngredient) {
        self.detection = detection
        self.isSelected = !detection.isAlreadyInPantry
        self.name = detection.name
        self.category = detection.category
        self.quantityText = String(detection.visibleCount ?? 1)
        self.unit = .pieces
    }

    /// The quantity to store, or `nil` if what the user typed isn't a
    /// usable number. `AddPantryItemUseCase` still has the final say.
    var quantity: Double? {
        let trimmed = quantityText.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value >= 0 else { return nil }
        return value
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
