import SwiftUI

enum IngredientEditorMode {
    case add(IngredientTemplate)
    case edit(Ingredient)
}

struct IngredientEditorView: View {
    let mode: IngredientEditorMode
    let inventory: InventoryService
    let onDone: () -> Void

    @State private var name: String
    @State private var category: String
    @State private var storageLocation: StorageLocation
    @State private var quantity: Quantity
    @State private var openedState: OpenedState
    @State private var hasExpiry: Bool
    @State private var expiryDate: Date
    @State private var lowStockThreshold: Double?
    @State private var errorMessage: String?

    init(mode: IngredientEditorMode, inventory: InventoryService, onDone: @escaping () -> Void) {
        self.mode = mode
        self.inventory = inventory
        self.onDone = onDone

        switch mode {
        case .add(let template):
            _name = State(initialValue: template.name)
            _category = State(initialValue: template.category.displayName)
            _storageLocation = State(initialValue: template.storageLocation)
            _quantity = State(initialValue: template.defaultQuantity)
            _openedState = State(initialValue: template.openedState)
            let defaultExpiry = template.expiryOffsetDays.flatMap {
                Calendar.current.date(byAdding: .day, value: $0, to: .now)
            }
            _hasExpiry = State(initialValue: defaultExpiry != nil)
            _expiryDate = State(initialValue: defaultExpiry ?? .now)
            _lowStockThreshold = State(initialValue: template.lowStockThreshold)
        case .edit(let ingredient):
            _name = State(initialValue: ingredient.name)
            _category = State(initialValue: ingredient.category.displayName)
            _storageLocation = State(initialValue: ingredient.storageLocation)
            _quantity = State(initialValue: ingredient.quantity)
            _openedState = State(initialValue: ingredient.openedState)
            _hasExpiry = State(initialValue: ingredient.expiryDate != nil)
            _expiryDate = State(initialValue: ingredient.expiryDate ?? .now)
            _lowStockThreshold = State(initialValue: ingredient.lowStockThreshold)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                IngredientArtwork(category: FoodCategory(named: category), size: 54)
                    .padding(.top, 4)

                VStack(spacing: 0) {
                    editorRow("Name") {
                        TextField("Ingredient", text: $name)
                            .multilineTextAlignment(.trailing)
                            .smartIngredientTextInput()
                    }

                    editorRow("Kind") {
                        Picker("Kind", selection: Binding(
                            get: { quantity.type },
                            set: { quantity = defaultQuantity(for: $0) }
                        )) {
                            Text("Count").tag(QuantityType.countable)
                            Text("Amount").tag(QuantityType.measurable)
                            Text("Package").tag(QuantityType.packaged)
                            Text("Staple").tag(QuantityType.staple)
                        }
                        .pickerStyle(.menu)
                    }

                    editorRow(quantitySectionTitle) {
                        QuantityInputView(quantity: $quantity)
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
                            Picker("State", selection: Binding(
                                get: { openedState },
                                set: { openedState = $0 }
                            )) {
                                Text("Unopened").tag(OpenedState.unopened)
                                Text("Opened").tag(OpenedState.opened)
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    if shouldOfferExpiry {
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
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(SmartFridgeTheme.surface.opacity(0.94))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                )

                Button {
                    save()
                } label: {
                    Text(primaryActionTitle == "Add" ? "Add to Kitchen" : "Save Changes")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(SmartFridgeTheme.warmAccent)
                        )
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
            .padding(20)
        }
        .background(SmartFridgeTheme.background.ignoresSafeArea())
        .navigationTitle(name)
        .smartInlineNavigationTitle()
        .alert("Couldn’t save ingredient", isPresented: Binding(
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
                .overlay(SmartFridgeTheme.separator)
                .padding(.leading, 14)
        }
    }

    private var quantitySectionTitle: String {
        switch quantity.type {
        case .countable: "Quantity"
        case .measurable: "Amount"
        case .packaged: "Size"
        case .staple: "Amount"
        }
    }

    private var shouldShowOpenedState: Bool {
        quantity.type == .packaged
    }

    private var shouldOfferExpiry: Bool {
        quantity.type != .staple
    }

    private var primaryActionTitle: String {
        switch mode {
        case .add: "Add"
        case .edit: "Save"
        }
    }

    private func defaultQuantity(for type: QuantityType) -> Quantity {
        switch type {
        case .countable:
            return .count(1)
        case .measurable:
            return .measure(100, unit: .grams)
        case .packaged:
            return .package(count: 1, unit: .pack, level: .full)
        case .staple:
            return .presence(.available)
        }
    }

    private func save() {
        do {
            try IngredientEditorSaveAction(
                mode: mode,
                name: name,
                category: FoodCategory(named: category),
                storageLocation: storageLocation,
                quantity: quantity,
                expiryDate: hasExpiry ? expiryDate : nil,
                openedState: shouldShowOpenedState ? openedState : .notApplicable,
                lowStockThreshold: lowStockThreshold
            ).execute(repository: inventory)
            onDone()
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "This ingredient could not be saved right now. Try again."
        }
    }
}

struct IngredientEditorSaveAction {
    var mode: IngredientEditorMode
    var name: String
    var category: FoodCategory
    var storageLocation: StorageLocation
    var quantity: Quantity
    var expiryDate: Date?
    var openedState: OpenedState
    var lowStockThreshold: Double?

    @MainActor
    func execute(repository: any HouseholdInventoryRepository) throws {
        switch mode {
        case .add:
            try AddInventoryItemUseCase(repository: repository).execute(AddInventoryItemRequest(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category,
                storageLocation: storageLocation,
                quantity: quantity,
                expiryDate: expiryDate,
                openState: openedState,
                lowStockThreshold: lowStockThreshold
            ))
        case .edit(let existing):
            try UpdateInventoryItemDetailsUseCase(repository: repository).execute(UpdateInventoryItemDetailsRequest(
                itemID: existing.id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category,
                storageLocation: storageLocation,
                quantity: quantity,
                expiryDate: expiryDate,
                openState: openedState,
                lowStockThreshold: lowStockThreshold
            ))
        }
    }
}

struct QuantityInputView: View {
    @Binding var quantity: Quantity

    var body: some View {
        switch quantity {
        case .count(let value, let unit):
            Stepper(value: Binding(
                get: { value },
                set: { quantity = .count(max(0, $0), unit: unit) }
            ), in: 0...99) {
                Text("\(value) \(unit.rawValue)")
            }
        case .measure(let value, let unit):
            HStack {
                TextField("Amount", value: Binding(
                    get: { value },
                    set: { quantity = .measure(max(0, $0), unit: unit) }
                ), format: .number.precision(.fractionLength(0...1)))
                .smartDecimalKeyboard()

                Picker("Unit", selection: Binding(
                    get: { unit },
                    set: { quantity = .measure(value, unit: $0) }
                )) {
                    ForEach([MeasurementUnit.grams, .kilograms, .millilitres, .litres]) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
            }
        case .package(let count, let unit, let level):
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
            .pickerStyle(.segmented)
        case .presence(let level):
            Picker("Amount", selection: Binding(
                get: { level },
                set: { quantity = .presence($0) }
            )) {
                ForEach(PresenceLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
