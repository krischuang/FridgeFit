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
    @Published var selectedCategory: InventoryCategorySummary = .all
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
        narrowedToCategory(inventory.useFirstItems(searchText: searchText, filter: selectedFilter))
    }

    /// Everything else matching the search, storage and category.
    var remainingItems: [PantryItem] {
        narrowedToCategory(inventory.remainingItems(searchText: searchText, filter: selectedFilter))
    }

    /// Whether the search and storage filter match anything, *before* the
    /// category tiles narrow it further.
    ///
    /// This is what decides whether the dashboard is on screen, so it
    /// deliberately ignores `selectedCategory`: a category that matches
    /// nothing must not take the tiles away with it, or the tile the user
    /// just tapped would vanish and leave them no way back to All.
    var hasResults: Bool {
        !storageMatchedItems.isEmpty
    }

    /// Whether anything survives all three narrowings and reaches the list.
    var hasVisibleItems: Bool {
        !useFirstItems.isEmpty || !remainingItems.isEmpty
    }

    /// Everything matching the search and storage filter, any category.
    ///
    /// Backs both `hasResults` and the tile counts, so a tile claiming "3
    /// items" is counting the same set that tapping it will show.
    private var storageMatchedItems: [PantryItem] {
        inventory.useFirstItems(searchText: searchText, filter: selectedFilter)
            + inventory.remainingItems(searchText: searchText, filter: selectedFilter)
    }

    /// How many items a tile would show if it were tapped.
    func itemCount(for category: InventoryCategorySummary) -> Int {
        storageMatchedItems.filter { category.includes($0.ingredient.category) }.count
    }

    private func narrowedToCategory(_ items: [PantryItem]) -> [PantryItem] {
        guard selectedCategory != .all else { return items }
        return items.filter { selectedCategory.includes($0.ingredient.category) }
    }

    /// Food added in the last `PantryItem.recentlyAddedWindow`, newest first.
    ///
    /// Drawn from the same filtered set as the list below it, so searching,
    /// switching to Freezer or tapping Produce narrows both together rather
    /// than leaving a section that contradicts the filter above it. Items
    /// here also stay in the main list: this highlights what just arrived, it
    /// does not move it somewhere the user then has to go looking for.
    func recentlyAddedItems(now: Date = Date()) -> [PantryItem] {
        (useFirstItems + remainingItems)
            .filter { $0.wasAddedRecently(now: now) }
            .sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
    }

    /// Whether an empty screen means "your kitchen is empty" rather than
    /// "nothing matched". Without this the user searches for something they
    /// don't have and is told their fridge is bare.
    var isShowingDefaultEmptyState: Bool {
        searchText.isEmpty && selectedFilter == .all && selectedCategory == .all
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

    /// Narrows to a category tile, or back to All when the active tile is
    /// tapped again.
    ///
    /// The second tap undoes the first because the tiles have no separate
    /// clear control: without this, narrowing to Produce would be a one-way
    /// trip unless the user noticed that All is itself a tile.
    func selectCategory(_ category: InventoryCategorySummary) {
        selectedCategory = (selectedCategory == category) ? .all : category
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
