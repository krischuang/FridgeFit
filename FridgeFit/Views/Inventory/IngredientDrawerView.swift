//
//  IngredientDrawerView.swift
//  FridgeFit
//

import SwiftUI

/// The contextual sheet for one kitchen item.
///
/// Opens at `.medium` showing what matters - how much is left, how urgent it
/// is, and the amount control - and expands to `.large` for details, history
/// and the destructive actions. My Kitchen stays visible behind it, which is
/// the point: this is a glance-and-adjust surface, not a screen.
///
/// Everything is edited as a draft and committed on Save. The one exception
/// is the destructive actions, which act immediately and are undoable from
/// the kitchen screen instead.
struct IngredientDrawerView: View {
    @Environment(\.dismiss) private var dismiss

    let itemID: UUID
    private let inventory: InventoryStore
    @Binding var detent: PresentationDetent
    let onRemoved: (UUID) -> Void

    @StateObject private var viewModel: IngredientDrawerViewModel
    @State private var showsDeleteConfirmation = false
    @State private var isEditingUsedAmount = false
    @State private var itemBeingEdited: PantryItem?
    @State private var isAdjustingQuantity = false
    @State private var repeatTask: Task<Void, Never>?
    /// FridgeFunds' stores. Optional because the environment default is
    /// `nil`; with no funds environment the price row simply never appears,
    /// rather than the drawer failing to build.
    @Environment(\.fundsEnvironment) private var funds
    @State private var isRecordingPrice = false
    /// Bumped after a price is written, purely to re-read `priceStore` -
    /// the store is a plain object, not observable, so nothing else would
    /// tell the row its value changed.
    @State private var priceRevision = 0

    init(
        itemID: UUID,
        inventory: InventoryStore,
        detent: Binding<PresentationDetent>,
        onRemoved: @escaping (UUID) -> Void
    ) {
        self.itemID = itemID
        self.inventory = inventory
        self._detent = detent
        self.onRemoved = onRemoved
        _viewModel = StateObject(wrappedValue: IngredientDrawerViewModel(itemID: itemID, inventory: inventory))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
                if let item = viewModel.visibleItem, let draft = viewModel.draft {
                    compactSummary(for: item)
                    usedAmountSection(draft: draft)
                    finishedAction(draft: draft)

                    if detent == .medium {
                        Image(systemName: "chevron.up")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                    }

                    if detent == .large {
                        expandedDetails(draft: draft)
                    }
                } else {
                    EmptyKitchenView(
                        title: "Ingredient not found",
                        message: "This item is no longer in your kitchen.",
                        actionTitle: nil,
                        action: nil
                    )
                }
            }
            .padding(FridgeFitTheme.Spacing.large)
            .padding(.bottom, FridgeFitTheme.Spacing.large)
        }
        .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if let draft = viewModel.draft, shouldShowSaveBar(for: draft) {
                saveBar(draft: draft)
            }
        }
        .confirmationDialog("Delete record?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { handle(await viewModel.deleteRecord()) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the item and its record from your kitchen.")
        }
        .alert("Kitchen update failed", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Try again.")
        }
        // Prices are stored per user in Firestore, so they have to be read
        // once before the row can show one. Cheap and idempotent.
        .task { await funds?.reload() }
        .sheet(isPresented: $isRecordingPrice) {
            if let item = viewModel.visibleItem, let funds {
                ItemPriceSheet(
                    itemName: item.name,
                    unit: item.unit.symbol,
                    quantityText: item.formattedQuantity,
                    currency: funds.displayCurrency,
                    suggestion: funds.priceBook.entry(forIngredientNamed: item.name)?.unitCost,
                    onSave: savePrice
                )
            }
        }
        .sheet(item: $itemBeingEdited) { item in
            NavigationStack {
                IngredientEditorView(
                    mode: .edit(item),
                    inventory: inventory,
                    onDone: {
                        itemBeingEdited = nil
                        dismiss()
                    }
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            viewModel.load()
        }
        .onDisappear {
            repeatTask?.cancel()
        }
    }

    private func compactSummary(for item: PantryItem) -> some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.medium) {
            IngredientArtwork(category: item.ingredient.category, size: 52)

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.name)
                        .font(FridgeFitTheme.Typography.screenTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: 6)

                    moreMenu()
                }

                Text("\(item.ingredient.category.displayName) · \(item.storage.title)")
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)

                Text(item.inventoryQuantity.displayText)
                    .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    .lineLimit(1)

                if let badge = statusBadge(for: item) {
                    Label(badge.title, systemImage: "clock.fill")
                        .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(badge.tint)
                        .padding(.horizontal, FridgeFitTheme.Spacing.small)
                        .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
                        .background(badge.tint.opacity(0.14), in: Capsule())
                }
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
        .accessibilityElement(children: .combine)
    }

    private func moreMenu() -> some View {
        Menu {
            if viewModel.draft?.openedState == .unopened {
                Button {
                    viewModel.markOpened()
                    Haptics.selection()
                } label: {
                    Label("Mark Opened", systemImage: "seal")
                }
            }

            Button {
                detent = .large
                itemBeingEdited = viewModel.visibleItem
                Haptics.selection()
            } label: {
                Label("Edit Details", systemImage: "pencil")
            }

            Button {
                detent = .large
                isAdjustingQuantity = true
                Haptics.selection()
            } label: {
                Label("Correct Quantity", systemImage: "slider.horizontal.3")
            }

            Button(role: .destructive) {
                discard()
            } label: {
                Label("Discard", systemImage: "trash")
            }

            Button(role: .destructive) {
                detent = .large
                showsDeleteConfirmation = true
            } label: {
                Label("Delete Record", systemImage: "xmark.bin")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3.weight(.medium))
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .accessibilityLabel("More")
    }

    private func usedAmountSection(draft: IngredientDraft) -> some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Text("Use from inventory")
                .font(FridgeFitTheme.Typography.supporting.weight(.bold))
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            HStack(spacing: 0) {
                RepeatButton(systemImage: "minus", accessibilityLabel: "Decrease amount used") {
                    changeUsedAmount(by: -1)
                } onStart: {
                    startRepeating(delta: -1)
                } onStop: {
                    stopRepeating()
                }

                Divider()

                Group {
                    if isEditingUsedAmount {
                        TextField("Used", text: $viewModel.usedAmountText)
                            .multilineTextAlignment(.center)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .usedAmountKeyboard(for: draft.baseQuantity)
                            .onSubmit {
                                viewModel.applyTypedUsedAmount(updateText: true)
                                isEditingUsedAmount = false
                            }
                            .onChange(of: viewModel.usedAmountText) { _, _ in
                                viewModel.applyTypedUsedAmount(updateText: false)
                            }
                    } else {
                        Button {
                            isEditingUsedAmount = true
                            viewModel.usedAmountText = UsedAmountFormatter.inputString(amount: draft.usedAmount, quantity: draft.baseQuantity)
                        } label: {
                            Text(UsedAmountFormatter.display(amount: draft.usedAmount, quantity: draft.baseQuantity))
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)

                Divider()

                RepeatButton(systemImage: "plus", accessibilityLabel: "Increase amount used") {
                    changeUsedAmount(by: 1)
                } onStart: {
                    startRepeating(delta: 1)
                } onStop: {
                    stopRepeating()
                }
            }
            .frame(height: 48)
            .background(FridgeFitTheme.ColorToken.disabledSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))

            Text("Left \(draft.remainingQuantity.displayText)")
                .font(FridgeFitTheme.Typography.metadata)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private func finishedAction(draft: IngredientDraft) -> some View {
        Button {
            viewModel.toggleFinished()
            Haptics.selection()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: draft.finished ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                Text("Finished")
                    .font(.headline)
                Spacer()
            }
            .foregroundStyle(draft.finished ? FridgeFitTheme.ColorToken.primary : FridgeFitTheme.ColorToken.textPrimary)
            .padding(.horizontal, FridgeFitTheme.Spacing.medium)
            .frame(height: 52)
            .background(draft.finished ? FridgeFitTheme.ColorToken.successBackground : FridgeFitTheme.ColorToken.card, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous).stroke(FridgeFitTheme.ColorToken.controlBorder, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func expandedDetails(draft: IngredientDraft) -> some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            completeDetails(draft: draft)

            if isAdjustingQuantity {
                correctQuantityEditor()
            }

            recentActivity(for: draft.original)

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
                Text("Actions")
                    .font(FridgeFitTheme.Typography.metadata.weight(.bold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .textCase(.uppercase)

                Button {
                    itemBeingEdited = viewModel.visibleItem
                } label: {
                    Label("Edit Details", systemImage: "pencil")
                }
                .buttonStyle(FridgeFitPrimaryButtonStyle())

                Button {
                    isAdjustingQuantity = true
                } label: {
                    Label("Correct Quantity", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(FridgeFitSecondaryButtonStyle())

                if funds != nil {
                    Button {
                        isRecordingPrice = true
                    } label: {
                        Label(recordedPrice == nil ? "Record Price" : "Update Price", systemImage: "tag")
                    }
                    .buttonStyle(FridgeFitSecondaryButtonStyle())
                }

                Button(role: .destructive) {
                    discard()
                } label: {
                    Label("Discard", systemImage: "trash")
                }
                .buttonStyle(FridgeFitSecondaryButtonStyle())

                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label("Delete Ingredient", systemImage: "trash")
                        .foregroundStyle(FridgeFitTheme.ColorToken.danger)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(FridgeFitTheme.ColorToken.card, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                                .stroke(FridgeFitTheme.ColorToken.errorText, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func completeDetails(draft: IngredientDraft) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Inventory information")
                .font(FridgeFitTheme.Typography.metadata.weight(.bold))
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, FridgeFitTheme.Spacing.medium)
                .padding(.top, FridgeFitTheme.Spacing.medium)
            DrawerInfoRow(title: "Storage", value: draft.storageLocation.title, systemImage: "refrigerator")
            DrawerInfoRow(title: "Category", value: draft.category.displayName, systemImage: "leaf")
            DrawerInfoRow(title: "Quantity", value: draft.baseQuantity.displayText, systemImage: "number")
            if let expiryDate = draft.expiryDate {
                DrawerInfoRow(title: "Use by", value: expiryDetail(expiryDate), systemImage: "calendar")
            }
            if let opened = openedLine(for: draft.openedState) {
                DrawerInfoRow(title: "Opened", value: opened, systemImage: "seal")
            }
            if funds != nil {
                DrawerInfoRow(title: "Price", value: priceDetail, systemImage: "tag")
            }
        }
        .drawerPanel()
    }

    // MARK: - Price

    /// What one unit of this item cost, if it has ever been recorded.
    ///
    /// Read straight from the price store rather than cached: a price is not
    /// part of `PantryItem`, it lives in FridgeFunds keyed by the item's id,
    /// and the Impact screen reads it the same way.
    private var recordedPrice: Money? {
        _ = priceRevision
        guard let funds, let item = viewModel.visibleItem else { return nil }
        return funds.priceStore.info(for: FridgeFitPantryReading.id(for: item))?.unitCost
    }

    private var priceDetail: String {
        guard let item = viewModel.visibleItem else { return "Not recorded" }
        guard let recordedPrice else { return "Not recorded" }
        return "\(recordedPrice.formatted()) per \(item.unit.symbol)"
    }

    /// Writes the price to FridgeFunds and remembers it against the
    /// ingredient's name, so re-buying the same thing suggests it back.
    ///
    /// Deliberately the same two calls `ImpactBudgetViewModel.savePrice`
    /// makes. The pantry item is not touched: a price is FridgeFunds' fact
    /// about an item, not part of the item.
    private func savePrice(_ unitCost: Decimal) {
        guard let funds, let item = viewModel.visibleItem, unitCost > 0 else { return }
        let id = FridgeFitPantryReading.id(for: item)
        let money = Money(unitCost, funds.displayCurrency)
        let existing = funds.priceStore.info(for: id)
        funds.priceStore.save(
            ItemPriceInfo(pantryItemID: id, unitCost: money, expiryDate: existing?.expiryDate)
        )
        funds.rememberPrice(of: item.name, unit: item.unit.symbol, unitCost: money)
        priceRevision += 1
    }

    private func correctQuantityEditor() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Correct Quantity")
                .font(.subheadline.weight(.bold))

            QuantityInputView(quantity: Binding(
                get: { viewModel.draft?.baseQuantity ?? .count(0) },
                set: { value in
                    viewModel.updateDraft {
                        $0.baseQuantity = value
                        $0.quantityWasCorrected = true
                        $0.clampUsedAmount()
                    }
                    viewModel.syncUsedAmountText()
                }
            ))
            .padding(14)
            .drawerPanel()

            Button {
                isAdjustingQuantity = false
            } label: {
                Text("Done")
                    .secondaryDrawerButton()
            }
        }
    }

    private func saveBar(draft: IngredientDraft) -> some View {
        let isEnabled = draft.canSave && viewModel.usedAmountInputIsValid
        return Button {
            save(draft)
        } label: {
            Text("Save")
                .font(FridgeFitTheme.Typography.button)
                .foregroundStyle(isEnabled ? .white : FridgeFitTheme.ColorToken.disabledText)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    isEnabled ? FridgeFitTheme.ColorToken.brandFill : FridgeFitTheme.ColorToken.disabledSurface,
                    in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .padding(.horizontal, FridgeFitTheme.Spacing.large)
        .padding(.top, FridgeFitTheme.Spacing.small)
        .padding(.bottom, FridgeFitTheme.Spacing.xSmall)
        .background(FridgeFitTheme.ColorToken.canvas.opacity(0.96))
    }

    private func recentActivity(for item: PantryItem) -> some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Text("Recent Activity")
                .font(FridgeFitTheme.Typography.sectionTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            let events = viewModel.recentActivity
            if events.isEmpty {
                Text("No recent activity")
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(FridgeFitTheme.Spacing.medium)
                    .fridgeFitCardSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(events) { event in
                        DrawerInfoRow(
                            title: event.kind.title,
                            value: activityValue(for: event),
                            systemImage: "clock"
                        )
                    }
                }
                .drawerPanel()
            }
        }
    }

    private func changeUsedAmount(by delta: Double, repeats: Bool = false, tick: Int = 0) {
        viewModel.changeUsedAmount(by: delta)
        if !repeats || tick.isMultiple(of: 5) {
            Haptics.selection()
        }
    }

    private func startRepeating(delta: Double) {
        stopRepeating()
        repeatTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(330))
            var delay = 170.0
            var tick = 0
            while !Task.isCancelled {
                tick += 1
                changeUsedAmount(by: delta, repeats: true, tick: tick)
                try? await Task.sleep(for: .milliseconds(Int(delay)))
                delay = max(55, delay * 0.72)
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }

    private func save(_ draft: IngredientDraft) {
        guard draft.canSave else { return }
        Task { handle(await viewModel.save()) }
    }

    private func discard() {
        Haptics.warning()
        Task { handle(await viewModel.discard()) }
    }

    private func handle(_ result: IngredientDrawerSaveResult) {
        switch result {
        case .saved:
            Haptics.success()
            dismiss()
        case .removed(let id):
            Haptics.success()
            onRemoved(id)
            dismiss()
        case .unchanged:
            break
        }
    }

    private func metadataLine(for item: PantryItem) -> String {
        var pieces = [item.storage.title]
        if let opened = openedLine(for: item.opened) {
            pieces.append(opened)
        }
        return pieces.joined(separator: " · ")
    }

    private func expiryLine(for item: PantryItem) -> String {
        guard let expiryDate = item.expiryDate else {
            return "No expiry date"
        }

        if let expiryState = ExpiryService.state(for: expiryDate) {
            return "Expires \(expiryState.title.lowercased()) · \(exactDate(expiryDate))"
        }

        return "Expires \(exactDate(expiryDate))"
    }

    private func expiryDetail(_ date: Date) -> String {
        guard let days = ExpiryService.state(for: date)?.daysUntilExpiry else {
            return exactDate(date)
        }

        let relative: String
        switch days {
        case ..<0:
            let elapsed = abs(days)
            relative = elapsed == 1 ? "Expired yesterday" : "Expired \(elapsed) days ago"
        case 0:
            relative = "Expires today"
        case 1:
            relative = "Expires tomorrow"
        default:
            relative = "\(days) days left"
        }
        return "\(exactDate(date)) · \(relative)"
    }

    private func shouldShowSaveBar(for draft: IngredientDraft) -> Bool {
        isAdjustingQuantity || isEditingUsedAmount || draft.canSave
    }

    private func expiryTint(for item: PantryItem) -> Color {
        item.expiryState?.urgency.tint ?? .secondary
    }

    private func openedLine(for state: OpenedState) -> String? {
        guard state != .notApplicable else { return nil }
        return state == .opened ? "Opened" : "Unopened"
    }

    private func statusBadge(for item: PantryItem) -> (title: String, tint: Color)? {
        if let expiryState = item.expiryState, expiryState.shouldPrioritise {
            return (expiryState.title, expiryState.urgency.tint)
        }
        if item.isLowStock {
            return ("Low", KitchenTheme.low)
        }
        return nil
    }

    private func exactDate(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }


    private func activityValue(for event: InventoryEvent) -> String {
        let time = event.date.formatted(date: .abbreviated, time: .shortened)
        if let note = event.note {
            return "\(note) · \(time)"
        }
        return time
    }
}

private struct DrawerInfoRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text(title)
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            Spacer(minLength: 12)

            Text(value)
                .font(FridgeFitTheme.Typography.supporting.weight(.medium))
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, FridgeFitTheme.Spacing.medium)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(KitchenTheme.separator)
                .padding(.leading, 48)
        }
    }
}

private struct RepeatButton: View {
    let systemImage: String
    let accessibilityLabel: LocalizedStringKey
    let action: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(KitchenTheme.forest)
                .frame(width: 52, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .onLongPressGesture(
            minimumDuration: 0.35,
            maximumDistance: 28,
            pressing: { isPressing in
                isPressing ? onStart() : onStop()
            },
            perform: {}
        )
    }
}

private extension View {
    func drawerPanel() -> some View {
        fridgeFitCardSurface()
    }

    func primaryDrawerButton() -> some View {
        font(FridgeFitTheme.Typography.button)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(FridgeFitTheme.ColorToken.brandFill, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
    }

    func secondaryDrawerButton() -> some View {
        font(FridgeFitTheme.Typography.button)
            .foregroundStyle(FridgeFitTheme.ColorToken.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(FridgeFitTheme.ColorToken.card, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
    }

    @ViewBuilder
    func usedAmountKeyboard(for quantity: Quantity) -> some View {
        switch quantity {
        case .count:
            keyboardType(.numberPad)
        case .measure, .package:
            keyboardType(.decimalPad)
        }
    }
}
