//
//  MyKitchenView.swift
//  FridgeFit
//

import SwiftUI

/// The Kitchen tab: everything the user has, grouped by where it is kept,
/// with whatever is about to go off pulled to the top.
///
/// ## Relationship to the Pantry tab
///
/// Both read the same `PantryRepository`. The Pantry tab is a flat list for
/// adding and correcting amounts; this is the spatial view - fridge, freezer,
/// pantry - plus expiry. Adding here goes through `AddPantryItemUseCase`
/// exactly as it does there, so an item added in one appears in the other
/// with no sync step.
///
/// ## No `NavigationStack` here
///
/// The ported original opened its own, which would have nested a second one
/// inside the stack `ContentView` already gives each tab - two navigation
/// bars and a back button that goes nowhere. The stack belongs to the tab.
struct MyKitchenView: View {
    @ObservedObject var inventory: InventoryStore
    @StateObject private var viewModel: MyKitchenViewModel
    @FocusState private var isSearchFocused: Bool

    init(inventory: InventoryStore) {
        self.inventory = inventory
        _viewModel = StateObject(wrappedValue: MyKitchenViewModel(inventory: inventory))
    }

    var body: some View {
        kitchenContent
            .background(KitchenTheme.background.ignoresSafeArea())
            .navigationTitle("")
            .task { await inventory.load() }
            .refreshable { await inventory.load() }
            .sheet(isPresented: $viewModel.showsAddIngredient) {
                AddInventoryIngredientView(inventory: inventory)
                    .presentationDetents([.large])
            }
            .sheet(item: $viewModel.selectedItem) { selection in
                IngredientDrawerView(
                    itemID: selection.id,
                    inventory: inventory,
                    detent: $viewModel.ingredientDrawerDetent,
                    onRemoved: { id in viewModel.itemWasRemoved(id) }
                )
                .presentationDetents([.medium, .large], selection: $viewModel.ingredientDrawerDetent)
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $viewModel.showsActivity) {
                KitchenActivityView(activities: viewModel.activities)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .alert("Kitchen couldn't load", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .safeAreaInset(edge: .bottom) {
                if let message = viewModel.lastMessage {
                    undoBar(message: message)
                }
            }
    }

    private var kitchenContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                let useSoon = viewModel.useFirstItems
                let remaining = viewModel.remainingItems
                let allVisible = useSoon + remaining

                kitchenHeader()

                if viewModel.isSearchPresented || !viewModel.searchText.isEmpty {
                    inlineSearchField
                }

                if viewModel.hasResults {
                    useFirstStrip(useSoon)

                    storageZone(
                        .pantry,
                        items: items(in: .pantry, from: allVisible),
                        accent: zoneAccent(.pantry),
                        note: "Dry goods and staples"
                    )
                    storageZone(
                        .fridge,
                        items: items(in: .fridge, from: allVisible),
                        accent: zoneAccent(.fridge),
                        note: "Fresh items to keep close"
                    )
                    storageZone(
                        .freezer,
                        items: items(in: .freezer, from: allVisible),
                        accent: zoneAccent(.freezer),
                        note: "Frozen stock"
                    )
                } else if inventory.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else if viewModel.isShowingDefaultEmptyState {
                    EmptyKitchenView(
                        title: "Your kitchen is empty",
                        message: "Add the ingredients you already have at home.",
                        actionTitle: "Add Ingredient",
                        action: { viewModel.showsAddIngredient = true }
                    )
                } else {
                    EmptyKitchenView(
                        title: "No ingredients found",
                        message: "Try a different search or storage filter.",
                        actionTitle: nil,
                        action: nil
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 80)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func kitchenHeader() -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("My Kitchen")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(greeting)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.showsActivity = true
            } label: {
                headerGlyph("clock", foreground: KitchenTheme.forest, background: KitchenTheme.surface)
            }
            .accessibilityLabel("Kitchen activity")

            Button {
                withAnimation(.snappy) {
                    viewModel.isSearchPresented = true
                }
                isSearchFocused = true
            } label: {
                headerGlyph("magnifyingglass", foreground: KitchenTheme.forest, background: KitchenTheme.surface)
            }
            .accessibilityLabel("Search ingredients")

            Button {
                viewModel.showsAddIngredient = true
            } label: {
                headerGlyph("plus", foreground: .white, background: KitchenTheme.warmAccent)
            }
            .accessibilityLabel("Add ingredient")
        }
    }

    /// The three header buttons differ only by symbol and colour. Drawn once
    /// so the 44pt hit target can't drift between them.
    private func headerGlyph(_ symbol: String, foreground: Color, background: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(foreground)
            .frame(width: 34, height: 34)
            .background(Circle().fill(background))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private var inlineSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search ingredients", text: $viewModel.searchText)
                .font(.body)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear search")
            }

            Button("Cancel") {
                withAnimation(.snappy) {
                    viewModel.searchText = ""
                    viewModel.isSearchPresented = false
                }
                isSearchFocused = false
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(KitchenTheme.warmAccent)
            .frame(minHeight: 44)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(KitchenTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(KitchenTheme.separator, lineWidth: 1)
        )
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private func useFirstStrip(_ items: [PantryItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Use First", subtitle: items.isEmpty ? "All clear" : "\(items.count) to check")

            if items.isEmpty {
                Text("Nothing needs attention right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(KitchenTheme.surface)
                    )
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            Button {
                                viewModel.select(item)
                            } label: {
                                IngredientTile(item: item, compact: true, accent: zoneAccent(item.storage))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func storageZone(_ location: StorageLocation, items: [PantryItem], accent: Color, note: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    Text(zoneLabel(location))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(accent.opacity(0.12)))

                    Text(items.count == 1 ? "1 item" : "\(items.count) items")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Capsule()
                .fill(accent.opacity(0.28))
                .frame(height: 3)
                .padding(.trailing, 210)
                .accessibilityHidden(true)

            if items.isEmpty {
                emptyZone(location)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            Button {
                                viewModel.select(item)
                            } label: {
                                IngredientTile(item: item, accent: accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(accent.opacity(0.16), lineWidth: 1)
        )
    }

    private func zoneLabel(_ location: StorageLocation) -> String {
        switch location {
        case .pantry: return "DRY"
        case .fridge: return "FRESH"
        case .freezer: return "COLD"
        }
    }

    private func emptyZone(_ location: StorageLocation) -> some View {
        Text("No \(location.title.lowercased()) items")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(minHeight: 54)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(KitchenTheme.tile.opacity(0.72))
            )
    }

    /// Items in one zone, most in need of attention first.
    ///
    /// Note this reads `item.storage`, not `item.storageLocation`: items
    /// added by the receipt scanner or the camera have no recorded location,
    /// and `storage` places them in the pantry rather than dropping them out
    /// of all three zones and off the screen.
    private func items(in location: StorageLocation, from items: [PantryItem]) -> [PantryItem] {
        items
            .filter { $0.storage == location }
            .sorted { priorityRank($0) > priorityRank($1) }
    }

    private func priorityRank(_ item: PantryItem) -> Int {
        if let urgency = item.expiryState?.urgency {
            return urgency.rawValue
        }
        return item.isLowStock ? 1 : 0
    }

    private func zoneAccent(_ location: StorageLocation) -> Color {
        switch location {
        case .pantry: return Color(red: 0.66, green: 0.52, blue: 0.34)
        case .fridge: return KitchenTheme.warmAccent
        case .freezer: return Color(red: 0.42, green: 0.61, blue: 0.72)
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func undoBar(message: String) -> some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            if viewModel.canUndoLastAction {
                Button("Undo") {
                    Task { await inventory.undoLastAction() }
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
            }

            Button {
                inventory.clearLastMessage()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 16)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(KitchenTheme.warmAccent)
                .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 5)
        )
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}

#Preview {
    NavigationStack {
        MyKitchenView(inventory: InventoryStore(
            pantryRepository: InMemoryPantryRepository(seedItems: [
                PantryItem(
                    ingredient: Ingredient(name: "Spinach", category: .produce),
                    quantity: 150,
                    unit: .grams,
                    expiryDate: Date(),
                    storageLocation: .fridge,
                    lowStockThreshold: 60
                ),
                PantryItem(
                    ingredient: Ingredient(name: "Rice", category: .grain),
                    quantity: 1,
                    unit: .kilograms,
                    storageLocation: .pantry
                ),
            ]),
            eventRepository: InMemoryInventoryEventRepository()
        ))
    }
}
