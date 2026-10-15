//
//  AddPantryItemView.swift
//  FridgeFit
//

import SwiftUI

/// Form for adding a new pantry item, presented as a sheet from
/// `PantryView`.
///
/// Just collects input - validation and duplicate checking happen in
/// `AddPantryItemUseCase` via `PantryViewModel`.
struct AddPantryItemView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: PantryViewModel
    /// Called when the user wants to edit the existing duplicate instead
    /// of adding a new one. Caller handles dismissing and presenting edit.
    var onEditExisting: (PantryItem) -> Void

    @State private var name: String = ""
    @State private var quantityText: String = ""
    @State private var unit: MeasurementUnit = .grams
    @State private var category: IngredientCategory = .other
    @State private var priceText: String = ""
    @State private var hasExpiry = false
    @State private var expiryDate = Date()
    @State private var priceError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Ingredient") {
                    TextField("Name", text: $name)
                        .accessibilityLabel("Ingredient name")
                        .accessibilityIdentifier("addItem.name")
                    Picker("Category", selection: $category) {
                        ForEach(IngredientCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                }
                Section("Quantity") {
                    TextField("Quantity", text: $quantityText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Quantity")
                        .accessibilityIdentifier("addItem.quantity")
                    Picker("Unit", selection: $unit) {
                        ForEach(MeasurementUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                }
                // optional - only used by the Budget tab to work out what's in your fridge
                Section {
                    HStack {
                        Text("$").foregroundStyle(.secondary)
                        TextField("What you paid (optional)", text: $priceText)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("addItem.price")
                    }
                    Toggle("Has an expiry date", isOn: $hasExpiry)
                        .accessibilityIdentifier("addItem.hasExpiry")
                    if hasExpiry {
                        DatePicker("Expires", selection: $expiryDate, displayedComponents: .date)
                    }
                } header: {
                    Text("Price & Expiry")
                } footer: {
                    Text("For the whole amount above. Shows up in the Budget tab.")
                }
                if let priceError {
                    Section {
                        InlineErrorBanner(message: priceError)
                            .listRowInsets(EdgeInsets())
                            .padding(.vertical, 2)
                    }
                }
                if let errorMessage = viewModel.errorMessage {
                    Section {
                        InlineErrorBanner(message: errorMessage)
                            .listRowInsets(EdgeInsets())
                            .padding(.vertical, 2)
                        if let duplicateItem = viewModel.duplicateItem {
                            Button {
                                onEditExisting(duplicateItem)
                            } label: {
                                Label("Update Existing Quantity", systemImage: "arrow.uturn.right.circle")
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Add to Pantry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Button("Add") { addItem() }
                            .accessibilityIdentifier("addItem.save")
                    }
                }
            }
        }
    }

    private func addItem() {
        let quantity = Double(quantityText) ?? -1
        let trimmedPrice = priceText.trimmingCharacters(in: .whitespaces)
        let price = Decimal(string: trimmedPrice, locale: Locale(identifier: "en_US_POSIX"))
        if !trimmedPrice.isEmpty, price == nil || price! < 0 {
            priceError = "Enter what you paid as a number, e.g. 4.50 - or leave it empty."
            return
        }
        priceError = nil
        Task {
            await viewModel.addItem(name: name, quantity: quantity, unit: unit, category: category,
                                    pricePaid: price, expiryDate: hasExpiry ? expiryDate : nil)
            if viewModel.errorMessage == nil {
                dismiss()
            }
        }
    }
}
