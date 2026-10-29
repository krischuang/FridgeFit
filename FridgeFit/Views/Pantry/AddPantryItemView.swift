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

    var body: some View {
        NavigationStack {
            Form {
                Section("Ingredient") {
                    TextField("Name", text: $name)
                        .accessibilityLabel("Ingredient name")
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
                    Picker("Unit", selection: $unit) {
                        ForEach(MeasurementUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit)
                        }
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
                            .tint(FridgeFitTheme.ColorToken.warningText)
                        }
                    }
                }
            }
            .navigationTitle("Add to Pantry")
            .numericKeyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Button("Add") { addItem() }
                    }
                }
            }
        }
    }

    private func addItem() {
        let quantity = Double(quantityText) ?? -1
        Task {
            await viewModel.addItem(name: name, quantity: quantity, unit: unit, category: category)
            if viewModel.errorMessage == nil {
                dismiss()
            }
        }
    }
}
