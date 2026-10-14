import SwiftUI

public struct SmartFridgeView: View {
    @State private var viewModel: MyKitchenViewModel
    @FocusState private var isSearchFocused: Bool

    @MainActor
    public init(inventory: InventoryService = InventoryService()) {
        _viewModel = State(initialValue: MyKitchenViewModel(inventory: inventory))
    }

    public var body: some View {
        NavigationStack {
            kitchenContent
                .background(SmartFridgeTheme.background.ignoresSafeArea())
                .navigationTitle("")
                .sheet(isPresented: $viewModel.showsAddIngredient) {
                    AddIngredientView(inventory: viewModel.inventory)
                        .presentationDetents([.large])
                }
                .sheet(item: $viewModel.selectedIngredient) { selection in
                    IngredientDrawerView(
                        ingredientID: selection.id,
                        inventory: viewModel.inventory,
                        detent: $viewModel.ingredientDrawerDetent,
                        onRemoved: { id in
                            viewModel.recordRemovedIngredient(id)
                        }
                    )
                    .presentationDetents([.medium, .large], selection: $viewModel.ingredientDrawerDetent)
                    .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $viewModel.showsActivity) {
                    KitchenActivityView(activities: viewModel.activities)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
                .alert("Kitchen couldn’t load", isPresented: Binding(
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
    }

    private var kitchenContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                let useSoon = viewModel.useFirstIngredients
                let remaining = viewModel.remainingIngredients
                let allVisible = useSoon + remaining

                kitchenHeader()

                if viewModel.isSearchPresented || !viewModel.searchText.isEmpty {
                    inlineSearchField
                }

                if viewModel.hasResults {
                    useFirstStrip(useSoon)

                    storageZone(
                        .pantry,
                        ingredients: ingredients(in: .pantry, from: allVisible),
                        accent: zoneAccent(.pantry),
                        note: "Dry goods and staples"
                    )
                    storageZone(
                        .fridge,
                        ingredients: ingredients(in: .fridge, from: allVisible),
                        accent: zoneAccent(.fridge),
                        note: "Fresh items to keep close"
                    )
                    storageZone(
                        .freezer,
                        ingredients: ingredients(in: .freezer, from: allVisible),
                        accent: zoneAccent(.freezer),
                        note: "Frozen stock"
                    )
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
                Text("Fridge Fit")
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
                Image(systemName: "clock")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(SmartFridgeTheme.forest)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(SmartFridgeTheme.surface))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Kitchen activity")

            Button {
                withAnimation(.snappy) {
                    viewModel.isSearchPresented = true
                }
                isSearchFocused = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(SmartFridgeTheme.forest)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(SmartFridgeTheme.surface))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Search ingredients")

            Button {
                viewModel.showsAddIngredient = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(SmartFridgeTheme.warmAccent))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Add ingredient")
        }
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
            .foregroundStyle(SmartFridgeTheme.warmAccent)
            .frame(minHeight: 44)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SmartFridgeTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(SmartFridgeTheme.separator, lineWidth: 1)
        )
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<18:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }

    private func useFirstStrip(_ ingredients: [Ingredient]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Use First", subtitle: ingredients.isEmpty ? "All clear" : "\(ingredients.count) to check")

            if ingredients.isEmpty {
                Text("Nothing needs attention right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(SmartFridgeTheme.surface)
                    )
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(ingredients) { ingredient in
                            Button {
                                viewModel.selectIngredient(ingredient)
                            } label: {
                                IngredientTile(ingredient: ingredient, compact: true, accent: zoneAccent(ingredient.storageLocation))
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

    private func storageZone(_ location: StorageLocation, ingredients: [Ingredient], accent: Color, note: String) -> some View {
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

                    Text("\(ingredients.count) items")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Capsule()
                .fill(accent.opacity(0.28))
                .frame(height: 3)
                .padding(.trailing, 210)
                .accessibilityHidden(true)

            if ingredients.isEmpty {
                emptyZone(location)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(ingredients) { ingredient in
                            Button {
                                viewModel.selectIngredient(ingredient)
                            } label: {
                                IngredientTile(ingredient: ingredient, accent: accent)
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
        case .pantry:
            "DRY"
        case .fridge:
            "FRESH"
        case .freezer:
            "COLD"
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
                    .fill(SmartFridgeTheme.tile.opacity(0.72))
            )
    }

    private func ingredients(in location: StorageLocation, from ingredients: [Ingredient]) -> [Ingredient] {
        ingredients
            .filter { $0.storageLocation == location }
            .sorted { lhs, rhs in
                priorityRank(lhs) > priorityRank(rhs)
            }
    }

    private func priorityRank(_ ingredient: Ingredient) -> Int {
        if let urgency = ExpiryService.state(for: ingredient.expiryDate)?.urgency {
            return urgency.rawValue
        }
        return ingredient.isLowStock ? 1 : 0
    }

    private func zoneAccent(_ location: StorageLocation) -> Color {
        switch location {
        case .pantry:
            Color(red: 0.66, green: 0.52, blue: 0.34)
        case .fridge:
            SmartFridgeTheme.warmAccent
        case .freezer:
            Color(red: 0.42, green: 0.61, blue: 0.72)
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
                    viewModel.undoLastAction()
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SmartFridgeTheme.warmAccent)
                .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 5)
        )
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}

#Preview {
    SmartFridgeView(inventory: InventoryService(persistence: nil, seedIfEmpty: true))
}
