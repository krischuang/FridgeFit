import Foundation
import Observation
import SwiftUI

/// Provides presentation state for the My Kitchen workspace.
///
/// The ViewModel owns screen-level UI state such as search text, selected
/// storage filter, Use First sections, activity sheet visibility, and
/// human-readable update messages. It delegates expiry prioritisation to
/// `IdentifyExpiringInventoryUseCase` and does not define expiry business
/// rules itself.
@MainActor
@Observable
final class MyKitchenViewModel {
    let inventory: InventoryService

    var searchText = ""
    var selectedFilter: InventoryFilter = .all
    var isSearchPresented = false
    var showsAddIngredient = false
    var showsActivity = false
    var selectedIngredient: IngredientSelection?
    var removedIngredientID: UUID?
    var ingredientDrawerDetent = PresentationDetent.medium
    var errorMessage: String?

    @ObservationIgnored private let identifyExpiringInventory: IdentifyExpiringInventoryUseCase

    init(inventory: InventoryService) {
        self.inventory = inventory
        errorMessage = inventory.loadErrorMessage
        identifyExpiringInventory = IdentifyExpiringInventoryUseCase(repository: inventory)
    }

    var useFirstIngredients: [InventoryItem] {
        identifyExpiringInventory.execute(searchText: searchText, filter: selectedFilter)
    }

    var remainingIngredients: [InventoryItem] {
        let useFirstIDs = Set(useFirstIngredients.map(\.id))
        return filteredActiveIngredients.filter { !useFirstIDs.contains($0.id) }
    }

    var hasResults: Bool {
        !useFirstIngredients.isEmpty || !remainingIngredients.isEmpty
    }

    var isShowingDefaultEmptyState: Bool {
        searchText.isEmpty && selectedFilter == .all
    }

    var lastMessage: String? {
        inventory.lastMessage
    }

    var canUndoLastAction: Bool {
        inventory.canUndoLastAction
    }

    var activities: [InventoryActivity] {
        inventory.inventoryActivities.sorted { $0.date > $1.date }
    }

    func selectFilter(_ filter: InventoryFilter) {
        selectedFilter = filter
    }

    func selectIngredient(_ ingredient: InventoryItem) {
        ingredientDrawerDetent = .medium
        selectedIngredient = IngredientSelection(id: ingredient.id)
    }

    func recordRemovedIngredient(_ id: UUID) {
        removedIngredientID = id
        selectedIngredient = nil
    }

    func undoLastAction() {
        do {
            try inventory.undoLastAction()
            removedIngredientID = nil
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Your kitchen couldn’t be saved right now. Your changes were not applied. Try again."
        }
    }

    private var filteredActiveIngredients: [InventoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return inventory.activeInventoryItems().filter { item in
            let matchesStorage = selectedFilter.storageLocation == nil || item.storageLocation == selectedFilter.storageLocation
            let matchesSearch = query.isEmpty
                || item.name.localizedCaseInsensitiveContains(query)
                || item.category.displayName.localizedCaseInsensitiveContains(query)
            return matchesStorage && matchesSearch
        }
    }
}

struct IngredientSelection: Identifiable {
    let id: UUID
}
