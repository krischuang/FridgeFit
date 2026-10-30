//
//  IngredientEditorView.swift
//  FridgeFit
//

import SwiftUI

/// Whether the editor is creating an item or changing one.
enum IngredientEditorMode {
    case add(IngredientTemplate)
    case edit(PantryItem)
}

/// One form for adding and editing kitchen items.
///
/// Fields appear only when they mean something: opened/unopened is offered
/// for packaged food and nothing else, because four loose tomatoes cannot be
/// "unopened" and asking would be asking for noise.
///
/// Nothing here is defaulted on the user's behalf beyond what the chosen
/// template already suggested. In particular, expiry is off unless the
/// template proposed a shelf life or the user turns it on - an item with no
/// date is honest, an item with a guessed date is not.
struct IngredientEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let mode: IngredientEditorMode
    @ObservedObject var inventory: InventoryStore
    let onDone: () -> Void

    @State private var name: String
    @State private var category: IngredientCategory
    @State private var storageLocation: StorageLocation
    @State private var quantity: Quantity
    @State private var openedState: OpenedState
    @State private var hasExpiry: Bool
    @State private var expiryDate: Date
    @State private var lowStockThreshold: Double?
    @State private var errorMessage: String?
    @State private var isSaving = false
    /// The real record identified by the pantry's existing duplicate rule.
    /// This view only presents recovery; it does not reimplement detection.
    @State private var detectedDuplicate: PantryItem?
    @State private var duplicateItemBeingEdited: PantryItem?
    /// Whether the user touched the amount. Decides whether the saved event
    /// says `quantityAdjusted` or `edited`, so correcting a typo is not
    /// recorded as having used something.
    @State private var quantityWasEdited = false

    init(mode: IngredientEditorMode, inventory: InventoryStore, onDone: @escaping () -> Void) {
        self.mode = mode
        self.inventory = inventory
        self.onDone = onDone

        switch mode {
        case .add(let template):
            _name = State(initialValue: template.name)
            _category = State(initialValue: template.category)
            _storageLocation = State(initialValue: template.storageLocation)
            _quantity = State(initialValue: template.defaultQuantity)
            _openedState = State(initialValue: template.openedState)
            let suggested = template.suggestedExpiryDate()
            _hasExpiry = State(initialValue: suggested != nil)
            _expiryDate = State(initialValue: suggested ?? .now)
            _lowStockThreshold = State(initialValue: template.lowStockThreshold)
        case .edit(let item):
            _name = State(initialValue: item.name)
            _category = State(initialValue: item.ingredient.category)
            _storageLocation = State(initialValue: item.storage)
            _quantity = State(initialValue: item.inventoryQuantity)
            _openedState = State(initialValue: item.opened)
            _hasExpiry = State(initialValue: item.expiryDate != nil)
            _expiryDate = State(initialValue: item.expiryDate ?? .now)
            _lowStockThreshold = State(initialValue: item.lowStockThreshold)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
                nameSection
                storageSection
                quantitySection
                expirySection
                if let detectedDuplicate {
                    duplicateRecoveryCard(for: detectedDuplicate)
                }
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.top, FridgeFitTheme.Spacing.medium)
            .padding(.bottom, FridgeFitTheme.Spacing.screen)
        }
        .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
        .navigationTitle(isAdding ? "Add Ingredient" : "Edit Ingredient")
        .navigationBarTitleDisplayMode(.inline)
        .numericKeyboardDoneButton()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(isSaveDisabled)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await save() }
            } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Label(isAdding ? "Add to Pantry" : "Save Changes", systemImage: isAdding ? "plus.circle" : "checkmark.circle")
                    }
                }
            }
            .buttonStyle(FridgeFitPrimaryButtonStyle())
            .disabled(isSaveDisabled)
            // While saving, the label is a bare ProgressView, so the button
            // would be announced with no name at all at exactly the moment
            // the user wants to know whether it took.
            .accessibilityLabel(
                isSaving
                    ? "Saving"
                    : (isAdding ? "Add to Pantry" : "Save Changes")
            )
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.top, FridgeFitTheme.Spacing.small)
            .padding(.bottom, FridgeFitTheme.Spacing.xSmall)
            .background(FridgeFitTheme.ColorToken.canvas.opacity(0.96))
        }
        .alert("Couldn't save ingredient", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $duplicateItemBeingEdited) { item in
            NavigationStack {
                IngredientEditorView(
                    mode: .edit(item),
                    inventory: inventory,
                    onDone: {
                        detectedDuplicate = nil
                        duplicateItemBeingEdited = nil
                    }
                )
            }
            .presentationDetents([.large])
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            HStack(spacing: FridgeFitTheme.Spacing.small) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                TextField("Search or enter ingredient…", text: $name)
                    .font(FridgeFitTheme.Typography.body.weight(.medium))
                    .accessibilityLabel("Ingredient name")
                if !name.isEmpty {
                    Button { name = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Clear ingredient name")
                }
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.medium)
            .frame(minHeight: 46)
            .fridgeFitCardSurface()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FridgeFitTheme.Spacing.small) {
                    ForEach(matchingTemplates) { template in
                        Button { apply(template) } label: {
                            Label(template.name, systemImage: template.name.caseInsensitiveCompare(name) == .orderedSame ? "checkmark" : "plus")
                        }
                        .buttonStyle(FridgeFitChipStyle(isSelected: template.name.caseInsensitiveCompare(name) == .orderedSame))
                    }
                }
            }

            HStack {
                Text("Category")
                    .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                Spacer()
                Picker("Category", selection: $category) {
                    ForEach(IngredientCategory.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
            Text("Storage Location")
                .font(FridgeFitTheme.Typography.caption.weight(.bold))
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .textCase(.uppercase)

            HStack(spacing: FridgeFitTheme.Spacing.xSmall) {
                ForEach(StorageLocation.allCases) { location in
                    Button { storageLocation = location } label: {
                        Label(location.title, systemImage: storageSymbol(for: location))
                            .font(FridgeFitTheme.Typography.metadata.weight(storageLocation == location ? .semibold : .regular))
                            .foregroundStyle(storageLocation == location ? FridgeFitTheme.ColorToken.textPrimary : FridgeFitTheme.ColorToken.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(storageLocation == location ? FridgeFitTheme.ColorToken.card : .clear, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(storageLocation == location ? .isSelected : [])
                }
            }
            .padding(4)
            .background(FridgeFitTheme.ColorToken.disabledSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
        }
    }

    private var quantitySection: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            HStack {
                Text("Quantity")
                    .font(FridgeFitTheme.Typography.supporting.weight(.bold))
                Spacer()
                Text(quantity.displayText)
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }

            Picker("Quantity type", selection: Binding(
                get: { quantity.type },
                set: { quantity = Self.defaultQuantity(for: $0); quantityWasEdited = true }
            )) {
                Text("Count").tag(QuantityType.countable)
                Text("Amount").tag(QuantityType.measurable)
                Text("Pack").tag(QuantityType.packaged)
            }
            .pickerStyle(.segmented)

            StitchQuantityControl(quantity: Binding(
                get: { quantity },
                set: { quantity = $0; quantityWasEdited = true }
            ))

            if shouldShowOpenedState {
                Picker("Package state", selection: $openedState) {
                    Text("Unopened").tag(OpenedState.unopened)
                    Text("Opened").tag(OpenedState.opened)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private var expirySection: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            HStack(spacing: FridgeFitTheme.Spacing.small) {
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                    .frame(width: 28, height: 28)
                    .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Track Expiry Date")
                        .font(FridgeFitTheme.Typography.supporting.weight(.bold))
                    Text("Smart reminders before waste")
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                }
                Spacer()
                Toggle("Track expiry date", isOn: $hasExpiry.animation(.snappy))
                    .labelsHidden()
                    .accessibilityLabel("Track an expiry date")
            }

            if hasExpiry {
                Divider()
                DatePicker("Use by", selection: $expiryDate, displayedComponents: .date)
                    .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                if let state = ExpiryService.state(for: expiryDate), state.shouldPrioritise {
                    Label("This item is \(state.title.lowercased()) and will be prioritised in recipe recommendations.", systemImage: "clock.fill")
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
                        .padding(FridgeFitTheme.Spacing.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FridgeFitTheme.ColorToken.warningBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))
                }
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private var matchingTemplates: [IngredientTemplate] {
        Array(InventoryTemplateCatalog.matching(name).prefix(5))
    }

    private func apply(_ template: IngredientTemplate) {
        name = template.name
        category = template.category
        storageLocation = template.storageLocation
        quantity = template.defaultQuantity
        openedState = template.openedState
        if let suggested = template.suggestedExpiryDate() {
            hasExpiry = true
            expiryDate = suggested
        }
    }

    private func storageSymbol(for location: StorageLocation) -> String {
        switch location {
        case .fridge: return "refrigerator"
        case .freezer: return "snowflake"
        case .pantry: return "cabinet"
        }
    }

    private var quantitySectionTitle: String {
        switch quantity.type {
        case .countable: return "Quantity"
        case .measurable: return "Amount"
        case .packaged: return "Size"
        }
    }

    /// Only packaged food can be opened or unopened.
    private var shouldShowOpenedState: Bool {
        quantity.type == .packaged
    }

    private var isAdding: Bool {
        switch mode {
        case .add: return true
        case .edit: return false
        }
    }

    private var isSaveDisabled: Bool {
        isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func duplicateRecoveryCard(for item: PantryItem) -> some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Label("Already in your fridge", systemImage: "exclamationmark.triangle.fill")
                .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.warningText)

            Text("\(item.name) is already tracked. Open the existing item to update its quantity or details instead of creating a second entry.")
                .font(FridgeFitTheme.Typography.metadata)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                duplicateItemBeingEdited = item
            } label: {
                Label("Update Existing Item", systemImage: "arrow.uturn.right.circle")
            }
            .buttonStyle(FridgeFitSecondaryButtonStyle())

            Button("Dismiss") {
                detectedDuplicate = nil
            }
            .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            .frame(minHeight: 44)
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .background(
            FridgeFitTheme.ColorToken.warningBackground,
            in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous)
                .stroke(FridgeFitTheme.ColorToken.warningText.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.name) already exists in your fridge")
        .accessibilityHint("Open the existing item to update it instead of creating a duplicate")
    }

    private static func defaultQuantity(for type: QuantityType) -> Quantity {
        switch type {
        case .countable: return .count(1)
        case .measurable: return .measure(100, unit: .grams)
        case .packaged: return .package(count: 1, unit: .pack, level: .full)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let resolvedOpenedState = shouldShowOpenedState ? openedState : .notApplicable
        let resolvedExpiry = hasExpiry ? expiryDate : nil

        do {
            switch mode {
            case .add:
                try await inventory.add(AddInventoryItemRequest(
                    name: name,
                    category: category,
                    storageLocation: storageLocation,
                    quantity: quantity,
                    expiryDate: resolvedExpiry,
                    openedState: resolvedOpenedState,
                    lowStockThreshold: lowStockThreshold
                ))
            case .edit(let item):
                try await inventory.updateDetails(UpdateInventoryItemDetailsRequest(
                    itemID: item.id,
                    name: name,
                    category: category,
                    storageLocation: storageLocation,
                    quantity: quantity,
                    expiryDate: resolvedExpiry,
                    openedState: resolvedOpenedState,
                    lowStockThreshold: lowStockThreshold,
                    quantityWasCorrected: quantityWasEdited
                ))
            }
            onDone()
        } catch let error as AddPantryItemError {
            guard case let .duplicateIngredient(existingName) = error else {
                errorMessage = error.errorDescription ?? "This ingredient could not be saved right now. Try again."
                return
            }

            detectedDuplicate = await existingInventoryItem(named: existingName)
            if detectedDuplicate == nil {
                errorMessage = error.errorDescription ?? "This ingredient already exists in your fridge."
            }
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "This ingredient could not be saved right now. Try again."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Resolves the item rejected by `AddPantryItemUseCase` using the same
    /// name-matching behaviour as the stored ingredient. Reload only if a
    /// cross-device change has not reached this screen's `InventoryStore`.
    private func existingInventoryItem(named name: String) async -> PantryItem? {
        if let item = inventory.items.first(where: { $0.ingredient.matches(name: name) }) {
            return item
        }

        await inventory.load()
        return inventory.items.first { $0.ingredient.matches(name: name) }
    }
}

/// Compact quantity control for the shared add/edit editor. It only converts
/// between quantity shapes when the user explicitly changes the type picker;
/// increments and units retain the existing `Quantity` representation.
private struct StitchQuantityControl: View {
    @Binding var quantity: Quantity

    private static let measureUnits: [MeasurementUnit] = [.grams, .kilograms, .milliliters, .liters]

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            HStack(spacing: FridgeFitTheme.Spacing.medium) {
                HStack(spacing: 0) {
                    quantityButton("minus", accessibilityLabel: "Decrease ingredient quantity", action: decrement)
                    Text(amountText)
                        .font(FridgeFitTheme.Typography.supporting.weight(.bold))
                        .monospacedDigit()
                        .frame(minWidth: 38, minHeight: 36)
                    quantityButton("plus", accessibilityLabel: "Increase ingredient quantity", action: increment)
                }
                .background(FridgeFitTheme.ColorToken.disabledSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))

                unitPicker
            }
        }
    }

    @ViewBuilder
    private var unitPicker: some View {
        switch quantity {
        case .count(_, let unit):
            unitChip(unit.symbol, isSelected: true) {}
        case .measure(let value, let selectedUnit):
            HStack(spacing: FridgeFitTheme.Spacing.xSmall) {
                ForEach(Self.measureUnits) { unit in
                    unitChip(unit.symbol, isSelected: unit == selectedUnit) {
                        quantity = .measure(value, unit: unit)
                    }
                }
            }
        case .package(let count, let selectedUnit, let level):
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FridgeFitTheme.Spacing.xSmall) {
                    ForEach(PackageUnit.allCases) { unit in
                        unitChip(unit.rawValue, isSelected: unit == selectedUnit) {
                            quantity = .package(count: count, unit: unit, level: level)
                        }
                    }
                }
            }
        }
    }

    private func unitChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : FridgeFitTheme.ColorToken.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, FridgeFitTheme.Spacing.small)
                .frame(minHeight: 36)
                .background(isSelected ? FridgeFitTheme.ColorToken.brandFill : FridgeFitTheme.ColorToken.disabledSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
    }

    private func quantityButton(
        _ systemImage: String,
        accessibilityLabel: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.bold))
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(accessibilityLabel)
    }

    private var amountText: String {
        switch quantity {
        case .count(let value, _): return "\(value)"
        case .measure(let value, _): return value.formatted(.number.precision(.fractionLength(0...1)))
        case .package(let count, _, _): return "\(count)"
        }
    }

    private func increment() {
        switch quantity {
        case .count(let value, let unit): quantity = .count(value + 1, unit: unit)
        case .measure(let value, let unit): quantity = .measure(value + 1, unit: unit)
        case .package(let count, let unit, let level): quantity = .package(count: count + 1, unit: unit, level: level)
        }
    }

    private func decrement() {
        switch quantity {
        case .count(let value, let unit): quantity = .count(max(0, value - 1), unit: unit)
        case .measure(let value, let unit): quantity = .measure(max(0, value - 1), unit: unit)
        case .package(let count, let unit, let level): quantity = .package(count: max(1, count - 1), unit: unit, level: level)
        }
    }
}

/// The amount control, shaped by which kind of quantity this is.
struct QuantityInputView: View {
    @Binding var quantity: Quantity

    /// Only the units a kitchen amount is actually measured in. Cups and
    /// spoons exist in `MeasurementUnit` for recipes, but nobody stores
    /// "3 tbsp of chicken" in a fridge.
    private static let storableUnits: [MeasurementUnit] = [.grams, .kilograms, .milliliters, .liters]

    var body: some View {
        switch quantity {
        case .count(let value, let unit):
            Stepper(value: Binding(
                get: { value },
                set: { quantity = .count(max(0, $0), unit: unit) }
            ), in: 0...99) {
                Text("\(value) \(unit.symbol)")
            }
        case .measure(let value, let unit):
            HStack {
                TextField("Amount", value: Binding(
                    get: { value },
                    set: { quantity = .measure(max(0, $0), unit: unit) }
                ), format: .number.precision(.fractionLength(0...1)))
                .multilineTextAlignment(.trailing)
                .kitchenDecimalKeyboard()

                Picker("Unit", selection: Binding(
                    get: { unit },
                    set: { quantity = .measure(value, unit: $0) }
                )) {
                    ForEach(Self.storableUnits) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.menu)
            }
        case .package(let count, let unit, let level):
            VStack(alignment: .trailing, spacing: 8) {
                Stepper(value: Binding(
                    get: { count },
                    set: { quantity = .package(count: max(1, $0), unit: unit, level: level) }
                ), in: 1...12) {
                    Text("\(count) \(unit.rawValue)\(count == 1 ? "" : "s")")
                }

                Picker("Unit", selection: Binding(
                    get: { unit },
                    set: { quantity = .package(count: count, unit: $0, level: level) }
                )) {
                    ForEach(PackageUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.menu)

                Picker("Left", selection: Binding(
                    get: { level },
                    set: { quantity = .package(count: count, unit: unit, level: $0) }
                )) {
                    ForEach(PackageLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}
