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
            VStack(spacing: 18) {
                IngredientArtwork(category: category, size: 54)
                    .padding(.top, 4)

                VStack(spacing: 0) {
                    editorRow("Name") {
                        TextField("Ingredient", text: $name)
                            .multilineTextAlignment(.trailing)
                            .kitchenIngredientTextInput()
                    }

                    editorRow("Category") {
                        Picker("Category", selection: $category) {
                            ForEach(IngredientCategory.allCases) { category in
                                Text(category.displayName).tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    editorRow("Kind") {
                        Picker("Kind", selection: Binding(
                            get: { quantity.type },
                            set: {
                                quantity = Self.defaultQuantity(for: $0)
                                quantityWasEdited = true
                            }
                        )) {
                            Text("Count").tag(QuantityType.countable)
                            Text("Amount").tag(QuantityType.measurable)
                            Text("Package").tag(QuantityType.packaged)
                        }
                        .pickerStyle(.menu)
                    }

                    editorRow(quantitySectionTitle) {
                        QuantityInputView(quantity: Binding(
                            get: { quantity },
                            set: {
                                quantity = $0
                                quantityWasEdited = true
                            }
                        ))
                    }

                    editorRow("Storage") {
                        Picker("Storage", selection: $storageLocation) {
                            ForEach(StorageLocation.allCases) { location in
                                Text(location.title).tag(location)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if shouldShowOpenedState {
                        editorRow("State") {
                            Picker("State", selection: $openedState) {
                                Text("Unopened").tag(OpenedState.unopened)
                                Text("Opened").tag(OpenedState.opened)
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    editorRow("Expiry") {
                        Toggle("Track", isOn: $hasExpiry.animation(.snappy))
                            .labelsHidden()
                    }

                    if hasExpiry {
                        editorRow("Date") {
                            DatePicker("Date", selection: $expiryDate, displayedComponents: .date)
                                .labelsHidden()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(KitchenTheme.surface.opacity(0.94))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                )

                Button {
                    Task { await save() }
                } label: {
                    Group {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text(isAdding ? "Add to Kitchen" : "Save Changes")
                                .font(.headline)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(KitchenTheme.warmAccent)
                    )
                }
                .disabled(isSaveDisabled)
                .opacity(isSaveDisabled ? 0.45 : 1)
            }
            .padding(20)
        }
        .background(KitchenTheme.background.ignoresSafeArea())
        .navigationTitle(name)
        .kitchenInlineNavigationTitle()
        .alert("Couldn't save ingredient", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func editorRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
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

            Divider()
                .overlay(KitchenTheme.separator)
                .padding(.leading, 14)
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
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "This ingredient could not be saved right now. Try again."
        } catch {
            errorMessage = error.localizedDescription
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
