//
//  MyKitchenView.swift
//  FridgeFit
//

import SwiftUI

/// The spatial inventory view: one repository-backed pantry, presented as
/// fridge, freezer and pantry locations. All mutations continue through
/// `InventoryStore`; this view owns only screen presentation state.
struct MyKitchenView: View {
    @ObservedObject var inventory: InventoryStore
    @ObservedObject var scannerViewModel: ReceiptScannerViewModel
    @StateObject private var viewModel: MyKitchenViewModel
    @FocusState private var isSearchFocused: Bool
    @State private var itemPendingDeletion: PantryItem?
    @State private var isPresentingSmartScan = false
    @State private var opensManualAddAfterSmartScan = false
    @State private var quickAddTemplate: IngredientTemplate?

    init(inventory: InventoryStore, scannerViewModel: ReceiptScannerViewModel) {
        self.inventory = inventory
        self.scannerViewModel = scannerViewModel
        _viewModel = StateObject(wrappedValue: MyKitchenViewModel(inventory: inventory))
    }

    var body: some View {
        kitchenContent
            .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .task { await inventory.load() }
            .refreshable { await inventory.load() }
            .sheet(isPresented: $viewModel.showsAddIngredient) {
                AddInventoryIngredientView(inventory: inventory)
                    .presentationDetents([.large])
            }
            .sheet(item: $quickAddTemplate) { template in
                NavigationStack {
                    IngredientEditorView(
                        mode: .add(template),
                        inventory: inventory,
                        onDone: { quickAddTemplate = nil }
                    )
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $isPresentingSmartScan, onDismiss: {
                if opensManualAddAfterSmartScan {
                    opensManualAddAfterSmartScan = false
                    viewModel.showsAddIngredient = true
                }
            }) {
                SmartScanPreviewView(
                    receiptScannerViewModel: scannerViewModel,
                    onReceiptFinished: { Task { await inventory.load() } },
                    onIngredientsFinished: { Task { await inventory.load() } },
                    onAddManually: { opensManualAddAfterSmartScan = true }
                )
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
            .confirmationDialog(
                "Remove \(itemPendingDeletion?.name ?? "ingredient")?",
                isPresented: Binding(
                    get: { itemPendingDeletion != nil },
                    set: { if !$0 { itemPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    guard let item = itemPendingDeletion else { return }
                    itemPendingDeletion = nil
                    Task { await remove(item) }
                }
                Button("Cancel", role: .cancel) { itemPendingDeletion = nil }
            } message: {
                Text("This removes the ingredient from your pantry. You can undo it after removal.")
            }
            .safeAreaInset(edge: .bottom) {
                if let message = viewModel.lastMessage {
                    undoBar(message: message)
                }
            }
    }

    private var kitchenContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: inventory.items.isEmpty ? FridgeFitTheme.Spacing.small : FridgeFitTheme.Spacing.medium) {
                appHeader
                screenHeader

                if inventory.items.isEmpty {
                    searchField
                    storageFilter
                } else {
                    storageFilter
                    searchField
                }

                if viewModel.hasResults {
                    inventoryDashboard
                    ingredientList
                        .padding(.top, -FridgeFitTheme.Spacing.xSmall)
                } else if inventory.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else if inventory.items.isEmpty {
                    emptyKitchenOnboarding
                } else {
                    filteredEmptyState
                }
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.top, inventory.items.isEmpty ? 2 : FridgeFitTheme.Spacing.xSmall)
            .padding(.bottom, FridgeFitTheme.Spacing.section)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var appHeader: some View {
        HStack(spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: "refrigerator")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 28, height: 28)
                .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))

            Text("FridgeFit")
                .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)

            Spacer()
        }
        .frame(minHeight: inventory.items.isEmpty ? 32 : 36)
    }

    private var screenHeader: some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
            VStack(alignment: .leading, spacing: 0) {
                Text("My Fridge")
                    .font(inventory.items.isEmpty ? .title2.weight(.bold) : .title.weight(.bold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    .minimumScaleFactor(0.8)

                Text("Make the most out of your pantry")
                    .font(inventory.items.isEmpty ? FridgeFitTheme.Typography.caption : FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                titleAction("arrow.clockwise", label: "Refresh inventory") {
                    Task { await inventory.load() }
                }

                titleAction("clock", label: "Kitchen activity", highlighted: true) {
                    viewModel.showsActivity = true
                }

                titleAction("viewfinder", label: "Smart Scan", highlighted: true) {
                    isPresentingSmartScan = true
                }

                Button {
                    viewModel.showsAddIngredient = true
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FridgeFitTheme.ColorToken.card)
                        .frame(width: 36, height: 36)
                        .background(FridgeFitTheme.ColorToken.primary, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Add ingredient")
            }
        }
    }

    private var storageFilter: some View {
        let compactAppearance = inventory.items.isEmpty
        return HStack(spacing: FridgeFitTheme.Spacing.xSmall) {
            ForEach(InventoryFilter.allCases) { filter in
                Button {
                    withAnimation(.snappy) {
                        viewModel.selectFilter(filter)
                    }
                } label: {
                    Text(filter.title)
                        .font(FridgeFitTheme.Typography.supporting.weight(filter == viewModel.selectedFilter ? .semibold : .regular))
                        .foregroundStyle(filter == viewModel.selectedFilter ? FridgeFitTheme.ColorToken.textPrimary : FridgeFitTheme.ColorToken.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: compactAppearance ? 38 : 44)
                        .background(
                            filter == viewModel.selectedFilter ? FridgeFitTheme.ColorToken.card : .clear,
                            in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityAddTraits(filter == viewModel.selectedFilter ? .isSelected : [])
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, compactAppearance ? 2 : 3)
        .background(FridgeFitTheme.ColorToken.disabledSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Storage filter")
    }

    private var searchField: some View {
        HStack(spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .accessibilityHidden(true)

            TextField("Search your pantry", text: $viewModel.searchText)
                .font(FridgeFitTheme.Typography.body)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, viewModel.searchText.isEmpty ? 6 : 0)
        .frame(minHeight: 44)
        .fridgeFitCardSurface()
    }

    private var emptyKitchenOnboarding: some View {
        VStack(spacing: FridgeFitTheme.Spacing.medium) {
            emptyFridgeHeroCard

            EmptyFridgeQuickAdds(
                templates: Array(InventoryTemplateCatalog.templates.prefix(8)),
                onSelect: { quickAddTemplate = $0 }
            )

            Label("Your ingredients are saved to your account and available across your signed-in devices.", systemImage: "lock")
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 2)
    }

    private var emptyFridgeHeroCard: some View {
        VStack(spacing: FridgeFitTheme.Spacing.medium) {
            EmptyFridgeHero()

            VStack(spacing: FridgeFitTheme.Spacing.xSmall) {
                Text("Your fridge is ready for its first ingredient")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Add a few fresh items or pantry staples so FridgeFit can track expiry dates and suggest low-waste meals.")
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                isPresentingSmartScan = true
            } label: {
                Label("Smart Scan Pantry", systemImage: "camera")
            }
            .buttonStyle(FridgeFitPrimaryButtonStyle())

            HStack(spacing: FridgeFitTheme.Spacing.small) {
                Button {
                    viewModel.showsAddIngredient = true
                } label: {
                    Label("Add Manually", systemImage: "plus")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(FridgeFitSecondaryButtonStyle())

                Button {} label: {
                    Label("Grocery List", systemImage: "book.closed")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(FridgeFitSecondaryButtonStyle())
                .disabled(true)
                .accessibilityHint("Grocery List is not available in this build")
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .background {
            ZStack(alignment: .topTrailing) {
                FridgeFitTheme.ColorToken.card
                Circle()
                    .fill(FridgeFitTheme.ColorToken.successBackground.opacity(0.7))
                    .frame(width: 112, height: 112)
                    .blur(radius: 22)
                    .offset(x: 32, y: -32)
            }
        }
        .fridgeFitCardSurface()
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your fridge is ready for its first ingredient")
        .accessibilityHint("Add an ingredient manually or scan a receipt to get started")
    }

    private var filteredEmptyState: some View {
        VStack(spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: viewModel.searchText.isEmpty ? "cabinet" : "magnifyingglass")
                .font(.title2.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 52, height: 52)
                .background(FridgeFitTheme.ColorToken.successBackground, in: Circle())
                .accessibilityHidden(true)

            Text(filteredEmptyTitle)
                .font(FridgeFitTheme.Typography.sectionTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            Text(filteredEmptyMessage)
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(FridgeFitTheme.Spacing.large)
        .fridgeFitCardSurface()
    }

    private var filteredEmptyTitle: String {
        if !viewModel.searchText.isEmpty {
            return "No results for \"\(viewModel.searchText)\""
        }
        return "No items in \(viewModel.selectedFilter.title)"
    }

    private var filteredEmptyMessage: String {
        if !viewModel.searchText.isEmpty {
            return "Try a different ingredient name or clear your search."
        }
        return "Add an ingredient to this storage location, or choose another filter."
    }

    private var inventoryDashboard: some View {
        GeometryReader { proxy in
            let gap = FridgeFitTheme.Spacing.small
            let heroWidth = (proxy.size.width - gap) * 0.54
            let gridWidth = proxy.size.width - gap - heroWidth

            HStack(spacing: gap) {
                priorityCard
                    .frame(width: heroWidth, height: proxy.size.height)

                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        summaryTile(.all)
                        summaryTile(.produce)
                    }
                    .frame(maxHeight: .infinity)

                    HStack(spacing: gap) {
                        summaryTile(.proteins)
                        summaryTile(.dairyAndPantry)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(width: gridWidth, height: proxy.size.height)
            }
        }
        .frame(height: 220)
    }

    private var priorityCard: some View {
        Group {
            if let priorityItem {
                Button {
                    viewModel.select(priorityItem)
                } label: {
                    urgentPriorityContent(priorityItem)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use soon: \(priorityItem.name), \(expiryText(for: priorityItem))")
            } else {
                allClearPriorityContent
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("No ingredients need attention")
            }
        }
    }

    private func urgentPriorityContent(_ item: PantryItem) -> some View {
        ZStack(alignment: .topLeading) {
            InventoryArtworkBackdrop(category: item.ingredient.category)
            LinearGradient(
                colors: [.clear, .black.opacity(0.16), .black.opacity(0.76)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Label("USE SOON", systemImage: "clock.fill")
                    .font(FridgeFitTheme.Typography.caption.weight(.bold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.card)
                    .padding(.horizontal, FridgeFitTheme.Spacing.small)
                    .padding(.vertical, 5)
                    .background(FridgeFitTheme.ColorToken.warningText, in: Capsule())

                Spacer(minLength: 0)

                Text(item.name)
                    .font(FridgeFitTheme.Typography.sectionTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.card)
                    .lineLimit(2)

                Label(expiryText(for: item), systemImage: "exclamationmark.triangle")
                    .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.card.opacity(0.92))
                    .lineLimit(2)
            }
            .padding(FridgeFitTheme.Spacing.medium)
        }
        .clipShape(RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
    }

    private var allClearPriorityContent: some View {
        ZStack(alignment: .topLeading) {
            InventoryArtworkBackdrop(category: nil)
            LinearGradient(
                colors: [.clear, FridgeFitTheme.ColorToken.primary.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                FridgeFitStatusBadge(title: "ALL CLEAR", systemImage: "checkmark.circle", tone: .success)
                Spacer(minLength: 0)
                Text("Nothing needs attention")
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.card)
                Text("Your tracked items are not use-soon.")
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.card.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(FridgeFitTheme.Spacing.medium)
        }
        .clipShape(RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
    }

    private func summaryTile(_ summary: InventoryCategorySummary) -> some View {
        let isAll = summary == .all
        return ZStack(alignment: .bottomLeading) {
            InventoryArtworkBackdrop(category: summary.representativeCategory, allItems: isAll)
            LinearGradient(
                colors: [.clear, .black.opacity(isAll ? 0.66 : 0.72)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(summary.title)
                    .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.card)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(categoryItemCount(for: summary))
                    .font(.caption2)
                    .foregroundStyle(FridgeFitTheme.ColorToken.card.opacity(0.84))
                    .lineLimit(1)
            }
            .padding(FridgeFitTheme.Spacing.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                .stroke(isAll ? FridgeFitTheme.ColorToken.primary : FridgeFitTheme.ColorToken.border, lineWidth: isAll ? 2 : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.title), \(categoryItemCount(for: summary))")
    }

    private var ingredientList: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pantry Ingredients")
                    .font(FridgeFitTheme.Typography.sectionTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

                Text("\(visibleItems.count)")
                    .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .padding(.horizontal, FridgeFitTheme.Spacing.small)
                    .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
                    .background(FridgeFitTheme.ColorToken.card, in: Capsule())
                    .overlay { Capsule().stroke(FridgeFitTheme.ColorToken.border, lineWidth: 1) }

                Spacer()
            }

            LazyVStack(spacing: 6) {
                ForEach(visibleItems) { item in
                    MyFridgeIngredientRow(
                        item: item,
                        onOpen: { viewModel.select(item) },
                        onDelete: { itemPendingDeletion = item }
                    )
                }
            }
        }
    }

    private var visibleItems: [PantryItem] {
        viewModel.useFirstItems + viewModel.remainingItems
    }

    private var priorityItem: PantryItem? {
        viewModel.useFirstItems.first
    }

    private func categoryItemCount(for summary: InventoryCategorySummary) -> String {
        let count = inventory.items.filter { summary.includes($0.ingredient.category) }.count
        return count == 1 ? "1 item" : "\(count) items"
    }

    private func expiryText(for item: PantryItem) -> String {
        guard let state = item.expiryState else { return "No expiry date" }
        return state.urgency == .expired ? "Expired" : "Expires \(state.title.lowercased())"
    }

    private func titleAction(_ systemImage: String, label: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 32, height: 32)
                .background(
                    highlighted ? FridgeFitTheme.ColorToken.successBackground : .clear,
                    in: Circle()
                )
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private func remove(_ item: PantryItem) async {
        do {
            try await inventory.deleteRecord(for: item.id)
        } catch {
            inventory.errorMessage = error.localizedDescription
        }
    }

    private func undoBar(message: String) -> some View {
        HStack(spacing: FridgeFitTheme.Spacing.medium) {
            Text(message)
                .font(FridgeFitTheme.Typography.supporting)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            if viewModel.canUndoLastAction {
                Button("Undo") {
                    Task { await inventory.undoLastAction() }
                }
                .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
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
        .padding(.leading, FridgeFitTheme.Spacing.large)
        .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
        .foregroundStyle(FridgeFitTheme.ColorToken.card)
        .background(FridgeFitTheme.ColorToken.primary, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
        .padding(.horizontal, FridgeFitTheme.Spacing.large)
        .padding(.bottom, FridgeFitTheme.Spacing.small)
    }
}

/// Empty-inventory visual derived from the Stitch empty-state reference.
/// It is decorative only; the surrounding card owns every real action.
private struct EmptyFridgeHero: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(FridgeFitTheme.ColorToken.successBackground.opacity(0.76))
                .frame(width: 92, height: 92)

            Circle()
                .stroke(FridgeFitTheme.ColorToken.primaryMuted.opacity(0.48), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                .frame(width: 68, height: 68)

            Image(systemName: "basket.fill")
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 54, height: 54)
                .background(FridgeFitTheme.ColorToken.card, in: Circle())

            Image(systemName: "leaf.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 24, height: 24)
                .background(FridgeFitTheme.ColorToken.successBackground, in: Circle())
                .offset(x: 34, y: -32)

            Image(systemName: "camera.macro")
                .font(.caption.weight(.bold))
                .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
                .frame(width: 22, height: 22)
                .background(FridgeFitTheme.ColorToken.warningBackground, in: Circle())
                .offset(x: -36, y: 32)
        }
        .frame(height: 96)
        .accessibilityHidden(true)
    }
}

/// Existing inventory templates rendered as suggestions. Selecting a tile
/// opens the existing editor; nothing is persisted until the user saves.
private struct EmptyFridgeQuickAdds: View {
    let templates: [IngredientTemplate]
    let onSelect: (IngredientTemplate) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label("Popular items to get started", systemImage: "sparkles")
                    .font(FridgeFitTheme.Typography.sectionTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

                Spacer()

                Text("Tap to add")
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(templates) { template in
                    Button {
                        onSelect(template)
                    } label: {
                        HStack(spacing: 6) {
                            IngredientArtwork(category: template.category, size: 24)

                            Text(template.name)
                                .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
                                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)

                            Spacer(minLength: 0)

                            Image(systemName: "plus")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                                .frame(width: 28, height: 44)
                        }
                        .padding(.leading, FridgeFitTheme.Spacing.small)
                        .padding(.trailing, 2)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .fridgeFitCardSurface()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(template.name)")
                    .accessibilityHint("Opens ingredient details before saving")
                }
            }
        }
    }
}

/// Stitch's four summary cards mapped onto FridgeFit's real ingredient
/// categories. They are informational: storage selection remains the only
/// inventory filter on this screen.
private enum InventoryCategorySummary: CaseIterable, Identifiable {
    case all
    case produce
    case proteins
    case dairyAndPantry

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All"
        case .produce: return "Produce"
        case .proteins: return "Proteins"
        case .dairyAndPantry: return "Dairy & Pantry"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .produce: return IngredientCategory.produce.symbolName
        case .proteins: return IngredientCategory.meat.symbolName
        case .dairyAndPantry: return "cabinet"
        }
    }

    var representativeCategory: IngredientCategory? {
        switch self {
        case .all:
            return nil
        case .produce:
            return .produce
        case .proteins:
            return .meat
        case .dairyAndPantry:
            return .dairy
        }
    }

    func includes(_ category: IngredientCategory) -> Bool {
        switch self {
        case .all:
            return true
        case .produce:
            return category == .produce
        case .proteins:
            return category == .meat
        case .dairyAndPantry:
            return [.dairy, .grain, .spice].contains(category)
        }
    }
}

/// The project has no food-photo assets. This retains the reference's
/// full-bleed, image-led card proportions using the existing category artwork
/// instead of introducing generated or misleading food imagery.
private struct InventoryArtworkBackdrop: View {
    let category: IngredientCategory?
    var allItems = false

    var body: some View {
        GeometryReader { proxy in
            let shortestSide = min(proxy.size.width, proxy.size.height)
            let artworkSize = max(28, shortestSide * 0.52)
            let circleSize = max(48, shortestSide * 1.08)

            ZStack {
                LinearGradient(
                    colors: [baseColor.opacity(0.74), baseColor.opacity(0.34)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(FridgeFitTheme.ColorToken.card.opacity(0.18))
                    .frame(width: circleSize, height: circleSize)
                    .offset(x: proxy.size.width * 0.24, y: -proxy.size.height * 0.15)

                if let category {
                    IngredientArtwork(category: category, size: artworkSize)
                        .scaleEffect(1.45)
                        .opacity(0.92)
                        .offset(x: proxy.size.width * 0.12, y: -proxy.size.height * 0.05)
                } else {
                    Image(systemName: allItems ? "square.grid.2x2.fill" : "checkmark.seal.fill")
                        .font(.system(size: artworkSize, weight: .semibold))
                        .foregroundStyle(FridgeFitTheme.ColorToken.card.opacity(0.42))
                        .offset(x: proxy.size.width * 0.1, y: -proxy.size.height * 0.05)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }

    private var baseColor: Color {
        category?.tint ?? FridgeFitTheme.ColorToken.primary
    }
}

/// Presentation-only list row shared by populated inventory surfaces. It
/// renders model-derived storage, quantity and expiry values; all actions are
/// supplied by the owning screen so it cannot create competing state.
private struct MyFridgeIngredientRow: View {
    let item: PantryItem
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: FridgeFitTheme.Spacing.xSmall) {
            Button(action: onOpen) {
                HStack(spacing: FridgeFitTheme.Spacing.small) {
                    IngredientArtwork(category: item.ingredient.category, size: 46)

                    VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                        Text(item.name)
                            .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
                            .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                            .lineLimit(2)

                        Text("\(item.ingredient.category.displayName) · \(item.storage.title) (\(item.inventoryQuantity.displayText))")
                            .font(FridgeFitTheme.Typography.caption)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                            .lineLimit(2)

                        Label(expiryText, systemImage: expirySymbol)
                            .font(FridgeFitTheme.Typography.caption.weight(expiryIsUrgent ? .semibold : .regular))
                            .foregroundStyle(expiryTint)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Opens ingredient details")

            Button(action: onOpen) {
                Image(systemName: "pencil")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(item.name)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(FridgeFitTheme.ColorToken.danger)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item.name)")
        }
        .padding(.horizontal, FridgeFitTheme.Spacing.medium)
        .padding(.vertical, FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private var expiryText: String {
        guard let state = item.expiryState else { return "No expiry date" }
        return state.urgency == .expired ? "Expired" : "Expires \(state.title.lowercased())"
    }

    private var expirySymbol: String {
        guard let state = item.expiryState else { return "calendar" }
        return state.shouldPrioritise ? "exclamationmark.triangle" : "calendar"
    }

    private var expiryIsUrgent: Bool {
        item.expiryState?.shouldPrioritise == true
    }

    private var expiryTint: Color {
        item.expiryState?.urgency.tint ?? FridgeFitTheme.ColorToken.textSecondary
    }

    private var accessibilityLabel: String {
        "\(item.name), \(item.ingredient.category.displayName), \(item.storage.title), \(item.inventoryQuantity.displayText), \(expiryText)"
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
                )
            ]),
            eventRepository: InMemoryInventoryEventRepository()
        ), scannerViewModel: ReceiptScannerViewModel(
            textRecognizer: MockReceiptTextRecognizer(lines: SampleReceiptPreviewData.lines),
            interpreter: MockReceiptIngredientInterpreter(),
            pantryRepository: InMemoryPantryRepository()
        ))
    }
}
