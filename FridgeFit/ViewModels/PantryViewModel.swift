//
//  PantryViewModel.swift
//  FridgeFit
//

import Combine
import Foundation

/// Presentation state and actions for the Pantry screen.
///
/// Doesn't decide validity or duplicates itself - that's delegated to
/// `AddPantryItemUseCase` / `UpdatePantryItemUseCase` /
/// `RemovePantryItemUseCase`. This just maps the result into something the
/// view can render.
@MainActor
final class PantryViewModel: ObservableObject {
    @Published private(set) var items: [PantryItem] = []
    @Published var errorMessage: String?
    /// Set when adding fails because the ingredient's a duplicate, so the
    /// view can offer "update the existing item" instead.
    @Published private(set) var duplicateItem: PantryItem?
    /// Set when removal fails. Separate from `errorMessage` so a removal
    /// alert never gets mixed up with a form's inline error.
    @Published var removalErrorMessage: String?
    @Published private(set) var isLoading = false

    private let pantryRepository: PantryRepository
    private let addPantryItemUseCase: AddPantryItemUseCase
    private let updatePantryItemUseCase: UpdatePantryItemUseCase
    private let removePantryItemUseCase: RemovePantryItemUseCase

    init(pantryRepository: PantryRepository = InMemoryPantryRepository()) {
        self.pantryRepository = pantryRepository
        self.addPantryItemUseCase = AddPantryItemUseCase(pantryRepository: pantryRepository)
        self.updatePantryItemUseCase = UpdatePantryItemUseCase(pantryRepository: pantryRepository)
        self.removePantryItemUseCase = RemovePantryItemUseCase(pantryRepository: pantryRepository)
    }

    func loadItems() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await pantryRepository.fetchAll()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Adds a pantry item. On failure, sets `errorMessage` for the view to
    /// display.
    func addItem(name: String, quantity: Double, unit: MeasurementUnit, category: IngredientCategory) async {
        errorMessage = nil
        duplicateItem = nil
        do {
            try await addPantryItemUseCase.execute(name: name, quantity: quantity, unit: unit, category: category)
            await loadItems()
        } catch let error as AddPantryItemError {
            errorMessage = error.errorDescription
            if case .duplicateIngredient(let existingName) = error {
                duplicateItem = items.first { $0.name.caseInsensitiveCompare(existingName) == .orderedSame }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Updates a pantry item's quantity/unit. On failure, sets
    /// `errorMessage`.
    func updateQuantity(for item: PantryItem, quantity: Double, unit: MeasurementUnit) async {
        errorMessage = nil
        do {
            try await updatePantryItemUseCase.execute(id: item.id, quantity: quantity, unit: unit)
            await loadItems()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Removes a pantry item. On failure (already removed elsewhere), sets
    /// `removalErrorMessage`.
    func removeItem(_ item: PantryItem) async {
        removalErrorMessage = nil
        do {
            try await removePantryItemUseCase.execute(id: item.id)
            await loadItems()
        } catch {
            removalErrorMessage = error.localizedDescription
        }
    }
}
