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
nonisolated struct AddPantryItemUseCase {
    private let pantryRepository: PantryRepository
    private let now: @Sendable () -> Date

    /// - Parameter now: injectable so a test can place an item inside or
    ///   outside the "Recently added" window without waiting.
    init(pantryRepository: PantryRepository, now: @escaping @Sendable () -> Date = { Date() }) {
        self.pantryRepository = pantryRepository
        self.now = now
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
    /// - Parameters:
    ///   - expiryDate: When it goes off, if the user said. The kitchen
    ///     editor supplies this; the receipt scanner and the camera review
    ///     sheet leave it `nil` because a detection carries no date, and
    ///     guessing one would put a false claim on the item.
    ///   - storageLocation: Where it is kept, when known. `nil` for every
    ///     caller that genuinely doesn't know - see `PantryItem.storage` for
    ///     how that is displayed.
    ///   - openedState: Only meaningful for packaged food.
    ///   - lowStockThreshold: The user's own "running low" line.
    ///   - packageUnit / packageLevel: The package reading that sits beside
    ///     `quantity`, for packaged quantities only.
    @discardableResult
    func execute(
        name: String,
        quantity: Double,
        unit: MeasurementUnit,
        category: IngredientCategory,
        expiryDate: Date? = nil,
        storageLocation: StorageLocation? = nil,
        openedState: OpenedState? = nil,
        lowStockThreshold: Double? = nil,
        packageUnit: PackageUnit? = nil,
        packageLevel: PackageLevel? = nil
    ) async throws -> PantryItem {
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
            unit: unit,
            expiryDate: expiryDate,
            storageLocation: storageLocation,
            openedState: openedState,
            lowStockThreshold: lowStockThreshold,
            packageUnit: packageUnit,
            packageLevel: packageLevel,
            // Stamped here, which is the one place a pantry item is ever
            // constructed: the kitchen editor, the receipt scanner, the
            // camera review sheet and the remote-camera review all reach the
            // pantry through this call, so "Recently added" sees every route
            // in without any of them having to know about it.
            addedAt: now()
        )
        try await pantryRepository.add(item)
        return item
    }
}
