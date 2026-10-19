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
    // where the optional price from the add form goes (the Budget tab)
    private let priceRecorder: PurchasePriceRecording?

    /// The repository is required rather than defaulted.
    ///
    /// The only sensible default would be an in-memory store, and silently
    /// writing a user's food into a dictionary that disappears is a worse
    /// failure than a compile error - the same reasoning `InventoryStore`
    /// already records. It also avoids constructing a main-actor type in a
    /// default-argument expression, which this project's
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting warns about.
    init(pantryRepository: PantryRepository, priceRecorder: PurchasePriceRecording? = nil) {
        self.pantryRepository = pantryRepository
        self.priceRecorder = priceRecorder
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
    func addItem(name: String, quantity: Double, unit: MeasurementUnit, category: IngredientCategory,
                 pricePaid: Decimal? = nil, expiryDate: Date? = nil) async {
        errorMessage = nil
        duplicateItem = nil
        do {
            // expiry is a real pantry field now (the Kitchen tab uses it too), so it
            // goes straight onto the item
            let added = try await addPantryItemUseCase.execute(name: name, quantity: quantity, unit: unit,
                                                               category: category, expiryDate: expiryDate)
            // price is only for the Budget tab, and only once the item is actually in
            if let pricePaid {
                priceRecorder?.recordPurchasePrice(pricePaid, for: added)
            }
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
