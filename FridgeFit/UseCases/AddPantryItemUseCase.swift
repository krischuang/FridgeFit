//
//  AddPantryItemUseCase.swift
//  FridgeFit
//

import Foundation

/// Adds a new pantry item, after checking the name/quantity and making
/// sure it's not already in the pantry.
///
/// All validation happens here, not in the view or view model, so there's
/// one place that can create a pantry item and it can't be skipped.
struct AddPantryItemUseCase {
    private let pantryRepository: PantryRepository

    init(pantryRepository: PantryRepository) {
        self.pantryRepository = pantryRepository
    }

    /// Validates and adds a pantry item, returning the item that was
    /// stored.
    ///
    /// **Duplicate rule:** if the ingredient is already in the pantry
    /// (matched via `Ingredient.matches(name:)`), the add is rejected
    /// instead of merging quantities or adding a second row. We don't know
    /// if the user forgot they already had some or actually bought more,
    /// so it's safer to just ask them to update the existing entry.
    ///
    /// - Throws: `AddPantryItemError.emptyIngredientName` if `name` is
    ///   blank, `AddPantryItemError.invalidQuantity` if `quantity` is
    ///   negative, or `AddPantryItemError.duplicateIngredient(name:)` if
    ///   the ingredient is already in the pantry.
    @discardableResult
    func execute(name: String, quantity: Double, unit: MeasurementUnit, category: IngredientCategory) async throws -> PantryItem {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw AddPantryItemError.emptyIngredientName
        }
        guard quantity >= 0 else {
            throw AddPantryItemError.invalidQuantity
        }
        if let existing = try await pantryRepository.fetchAll().first(where: { $0.ingredient.matches(name: trimmedName) }) {
            throw AddPantryItemError.duplicateIngredient(name: existing.name)
        }

        let item = PantryItem(
            ingredient: Ingredient(name: trimmedName, category: category),
            quantity: quantity,
            unit: unit
        )
        try await pantryRepository.add(item)
        return item
    }
}
