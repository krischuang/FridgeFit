//
//  MyKitchenViewModel.swift
//  FridgeFit
//

import Combine
import Foundation
import SwiftUI

/// Screen state for the Kitchen tab.
///
/// Owns only presentation concerns - search text, the storage filter, which
/// sheet is open. The food itself lives in `InventoryStore`, and expiry
/// prioritisation is `IdentifyExpiringInventoryUseCase`'s rule, not this
/// type's. Splitting it that way means the "Use First" policy can be tested
/// without a view model and changed without touching the screen.
@MainActor
final class MyKitchenViewModel: ObservableObject {
    let inventory: InventoryStore

    @Published var searchText = ""
    @Published var selectedFilter: InventoryFilter = .all
    @Published var isSearchPresented = false
    @Published var showsAddIngredient = false
    @Published var showsActivity = false
    @Published var selectedItem: PantryItemSelection?
    @Published var ingredientDrawerDetent = PresentationDetent.medium

    init(inventory: InventoryStore) {
        self.inventory = inventory
    }

    /// Food to use before it goes off, most urgent first.
    var useFirstItems: [PantryItem] {
        inventory.useFirstItems(searchText: searchText, filter: selectedFilter)
    }

    /// Everything else matching the search and filter.
    var remainingItems: [PantryItem] {
        inventory.remainingItems(searchText: searchText, filter: selectedFilter)
    }

    var hasResults: Bool {
        !useFirstItems.isEmpty || !remainingItems.isEmpty
    }

    /// Food added in the last `PantryItem.recentlyAddedWindow`, newest first.
    ///
    /// Drawn from the same filtered set as the list below it, so searching or
    /// switching to Freezer narrows both together rather than leaving a
    /// section that contradicts the filter above it. Items here also stay in
    /// the main list: this highlights what just arrived, it does not move it
    /// somewhere the user then has to go looking for.
    func recentlyAddedItems(now: Date = Date()) -> [PantryItem] {
        (useFirstItems + remainingItems)
            .filter { $0.wasAddedRecently(now: now) }
            .sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
    }

    /// Whether an empty screen means "your kitchen is empty" rather than
    /// "nothing matched". Without this the user searches for something they
    /// don't have and is told their fridge is bare.
    var isShowingDefaultEmptyState: Bool {
        searchText.isEmpty && selectedFilter == .all
    }

    var lastMessage: String? { inventory.lastMessage }

    var canUndoLastAction: Bool { inventory.canUndoLastAction }

    var activities: [InventoryEvent] { inventory.events }

    var errorMessage: String? {
        get { inventory.errorMessage }
        set { inventory.errorMessage = newValue }
    }

    func selectFilter(_ filter: InventoryFilter) {
        selectedFilter = filter
    }

    func select(_ item: PantryItem) {
        ingredientDrawerDetent = .medium
        selectedItem = PantryItemSelection(id: item.id)
    }

    /// Closes the drawer after the item it was showing has gone.
    func itemWasRemoved(_ id: UUID) {
        selectedItem = nil
    }
}

/// Identifies the drawer's subject by id rather than by value.
///
/// The drawer re-reads the item from the store on every change, so holding a
/// copy here would leave the sheet showing a stale amount the moment the
/// user adjusted it.
struct PantryItemSelection: Identifiable {
    let id: UUID
}
