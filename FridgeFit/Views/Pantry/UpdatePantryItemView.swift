//
//  UpdatePantryItemView.swift
//  FridgeFit
//

import SwiftUI

/// Form for updating a pantry item's quantity, presented as a sheet -
/// either by tapping the item, or via the duplicate-ingredient error's
/// "update instead" guidance.
struct UpdatePantryItemView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: PantryViewModel
    let item: PantryItem

    @State private var quantityText: String
    @State private var unit: MeasurementUnit

    init(viewModel: PantryViewModel, item: PantryItem) {
        self.viewModel = viewModel
        self.item = item
        _quantityText = State(initialValue: item.formattedQuantity.components(separatedBy: " ").first ?? "")
        _unit = State(initialValue: item.unit)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(item.name) {
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
                    }
                }
            }
            .navigationTitle("Update Quantity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                    }
                }
            }
        }
    }

    private func save() {
        let quantity = Double(quantityText) ?? -1
        Task {
            await viewModel.updateQuantity(for: item, quantity: quantity, unit: unit)
            if viewModel.errorMessage == nil {
                dismiss()
            }
        }
    }
}
