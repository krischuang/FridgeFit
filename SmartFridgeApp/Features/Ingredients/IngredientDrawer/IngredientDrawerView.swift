import SwiftUI

struct IngredientDrawerView: View {
    @Environment(\.dismiss) private var dismiss

    let ingredientID: UUID
    @Binding var detent: PresentationDetent
    let onRemoved: (UUID) -> Void

    @State private var viewModel: IngredientDrawerViewModel
    @State private var showsDeleteConfirmation = false
    @State private var isEditingUsedAmount = false
    @State private var isEditingDetails = false
    @State private var isAdjustingQuantity = false
    @State private var repeatTask: Task<Void, Never>?

    init(
        ingredientID: UUID,
        inventory: InventoryService,
        detent: Binding<PresentationDetent>,
        onRemoved: @escaping (UUID) -> Void
    ) {
        self.ingredientID = ingredientID
        self._detent = detent
        self.onRemoved = onRemoved
        _viewModel = State(initialValue: IngredientDrawerViewModel(itemID: ingredientID, repository: inventory))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let ingredient = viewModel.visibleIngredient, let draft = viewModel.draft {
                    compactSummary(for: ingredient)
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
            .padding(20)
            .padding(.bottom, 90)
        }
        .background(SmartFridgeTheme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if let draft = viewModel.draft {
                saveBar(draft: draft)
            }
        }
        .confirmationDialog("Delete record?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                handle(viewModel.deleteRecord())
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
        .onAppear {
            viewModel.load()
        }
        .onDisappear {
            repeatTask?.cancel()
        }
    }

    private func compactSummary(for ingredient: Ingredient) -> some View {
        HStack(alignment: .center, spacing: 14) {
            IngredientArtwork(category: ingredient.category, size: 42)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ingredient.name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: 6)

                    moreMenu()
                }

                HStack(spacing: 8) {
                    Text(ingredient.quantity.displayText)
                        .font(.headline.weight(.medium))

                    if let badge = statusBadge(for: ingredient) {
                        Text(badge.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(badge.tint)
                            .padding(.horizontal, 7)
                            .frame(height: 22)
                            .background(Capsule().fill(badge.tint.opacity(0.12)))
                    }
                }

                Text(metadataLine(for: ingredient))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(expiryLine(for: ingredient))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(expiryTint(for: ingredient))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SmartFridgeTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(SmartFridgeTheme.separator, lineWidth: 1)
        )
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
                isEditingDetails = true
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
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .accessibilityLabel("More")
    }

    private func usedAmountSection(draft: IngredientDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Used")
                .font(.subheadline.weight(.bold))

            HStack(spacing: 0) {
                RepeatButton(systemImage: "minus") {
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
                            .smartUsedAmountKeyboard(for: draft.baseQuantity)
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

                RepeatButton(systemImage: "plus") {
                    changeUsedAmount(by: 1)
                } onStart: {
                    startRepeating(delta: 1)
                } onStop: {
                    stopRepeating()
                }
            }
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SmartFridgeTheme.surface.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )

            Text("Left \(draft.remainingQuantity.displayText)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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
            .foregroundStyle(draft.finished ? SmartFridgeTheme.forest : .primary)
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(draft.finished ? SmartFridgeTheme.tile : SmartFridgeTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(draft.finished ? SmartFridgeTheme.warmAccent : Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func expandedDetails(draft: IngredientDraft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            completeDetails(draft: draft)

            if isEditingDetails {
                inlineEditor()
            }

            if isAdjustingQuantity {
                correctQuantityEditor()
            }

            recentActivity(for: draft.original)

            VStack(spacing: 10) {
                Button {
                    isEditingDetails = true
                } label: {
                    Label("Edit Details", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    isAdjustingQuantity = true
                } label: {
                    Label("Correct Quantity", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    discard()
                } label: {
                    Label("Discard", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label("Delete Record", systemImage: "xmark.bin")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func completeDetails(draft: IngredientDraft) -> some View {
        VStack(spacing: 0) {
            DrawerInfoRow(title: "Storage", value: draft.storageLocation.title, systemImage: "refrigerator")
            DrawerInfoRow(title: "Category", value: draft.category.displayName, systemImage: "leaf")
            if let expiryDate = draft.expiryDate {
                DrawerInfoRow(title: "Expiry Date", value: exactDate(expiryDate), systemImage: "calendar")
            }
            if let opened = openedLine(for: draft.openedState) {
                DrawerInfoRow(title: "Opened", value: opened, systemImage: "seal")
            }
        }
        .drawerPanel()
    }

    private func inlineEditor() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit Details")
                .font(.subheadline.weight(.bold))

            VStack(spacing: 0) {
                editorRow("Name") {
                    TextField("Name", text: Binding(
                        get: { viewModel.draft?.name ?? "" },
                        set: { value in viewModel.updateDraft { $0.name = value } }
                    ))
                    .multilineTextAlignment(.trailing)
                    .smartIngredientTextInput()
                }

                editorRow("Storage") {
                    Picker("Storage", selection: Binding(
                        get: { viewModel.draft?.storageLocation ?? .fridge },
                        set: { value in viewModel.updateDraft { $0.storageLocation = value } }
                    )) {
                        ForEach(StorageLocation.allCases) { location in
                            Text(location.title).tag(location)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                editorRow("Category") {
                    Picker("Category", selection: Binding(
                        get: { viewModel.draft?.category ?? .other },
                        set: { value in viewModel.updateDraft { $0.category = value } }
                    )) {
                        ForEach(FoodCategory.allCases) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if viewModel.draft?.baseQuantity.type != .staple {
                    editorRow("Expiry") {
                        DatePicker(
                            "Expiry",
                            selection: Binding(
                                get: { viewModel.draft?.expiryDate ?? .now },
                                set: { value in viewModel.updateDraft { $0.expiryDate = value } }
                            ),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                    }
                }

                if viewModel.draft?.openedState != .notApplicable {
                    editorRow("Opened") {
                        Picker("Opened", selection: Binding(
                            get: { viewModel.draft?.openedState ?? .unopened },
                            set: { value in viewModel.updateDraft { $0.openedState = value } }
                        )) {
                            Text("Unopened").tag(OpenedState.unopened)
                            Text("Opened").tag(OpenedState.opened)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .drawerPanel()

            Button {
                isEditingDetails = false
            } label: {
                Text("Done")
                    .secondaryDrawerButton()
            }
        }
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
        Button {
            save(draft)
        } label: {
            Text("Save")
                .primaryDrawerButton()
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)
        }
        .buttonStyle(.plain)
        .disabled(!draft.canSave || !viewModel.usedAmountInputIsValid)
        .opacity(draft.canSave && viewModel.usedAmountInputIsValid ? 1 : 0.45)
    }

    private func recentActivity(for ingredient: Ingredient) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Activity")
                .font(.subheadline.weight(.bold))

            let events = viewModel.recentActivity
            if events.isEmpty {
                Text("No recent activity")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(SmartFridgeTheme.surface)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(events) { event in
                        DrawerInfoRow(
                            title: eventTitle(for: event.kind),
                            value: activityValue(for: event),
                            systemImage: "clock"
                        )
                    }
                }
                .drawerPanel()
            }
        }
    }

    private func editorRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            content()
                .font(.subheadline)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(SmartFridgeTheme.separator)
                .padding(.leading, 14)
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
        handle(viewModel.save())
    }

    private func discard() {
        Haptics.warning()
        handle(viewModel.discard())
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

    private func metadataLine(for ingredient: Ingredient) -> String {
        var pieces = [ingredient.storageLocation.title]
        if let opened = openedLine(for: ingredient.openedState) {
            pieces.append(opened)
        }
        return pieces.joined(separator: " · ")
    }

    private func expiryLine(for ingredient: Ingredient) -> String {
        guard let expiryDate = ingredient.expiryDate else {
            return "No expiry date"
        }

        if let expiryState = ExpiryService.state(for: expiryDate) {
            return "Expires \(expiryState.title.lowercased()) · \(exactDate(expiryDate))"
        }

        return "Expires \(exactDate(expiryDate))"
    }

    private func expiryTint(for ingredient: Ingredient) -> Color {
        ExpiryService.state(for: ingredient.expiryDate)?.urgency.tint ?? .secondary
    }

    private func openedLine(for state: OpenedState) -> String? {
        guard state != .notApplicable else { return nil }
        return state == .opened ? "Opened" : "Unopened"
    }

    private func statusBadge(for ingredient: Ingredient) -> (title: String, tint: Color)? {
        if let expiryState = ExpiryService.state(for: ingredient.expiryDate), expiryState.shouldPrioritise {
            return (expiryState.title, expiryState.urgency.tint)
        }
        if ingredient.isLowStock {
            return ("Low", SmartFridgeTheme.low)
        }
        return nil
    }

    private func exactDate(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }

    private func eventTitle(for kind: InventoryEventKind) -> String {
        switch kind {
        case .added: "Added"
        case .used: "Used"
        case .quantityAdjusted: "Adjusted"
        case .opened: "Opened"
        case .finished: "Finished"
        case .discarded: "Discarded"
        case .deleted: "Deleted"
        case .edited: "Edited"
        }
    }

    private func activityValue(for event: InventoryEvent) -> String {
        let time = event.date.formatted(date: .abbreviated, time: .shortened)
        if let note = displayNote(for: event.note) {
            return "\(note) · \(time)"
        }
        return time
    }

    private func displayNote(for note: String?) -> String? {
        guard let note else { return nil }
        return note == "Seeded" ? "Added from starter list" : note
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
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(SmartFridgeTheme.separator)
                .padding(.leading, 48)
        }
    }
}

private struct RepeatButton: View {
    let systemImage: String
    let action: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(SmartFridgeTheme.forest)
                .frame(width: 52, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SmartFridgeTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        )
    }

    func primaryDrawerButton() -> some View {
        font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SmartFridgeTheme.warmAccent)
            )
    }

    func secondaryDrawerButton() -> some View {
        font(.headline)
            .foregroundStyle(SmartFridgeTheme.forest)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SmartFridgeTheme.tile)
            )
    }

    @ViewBuilder
    func smartUsedAmountKeyboard(for quantity: Quantity) -> some View {
        #if os(iOS)
        switch quantity {
        case .count, .presence:
            keyboardType(.numberPad)
        case .measure, .package:
            keyboardType(.decimalPad)
        }
        #else
        self
        #endif
    }
}
