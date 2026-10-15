import SwiftUI

// sheet for attaching a price + expiry to one pantry item. FridgeFit's pantry has
// neither, and the "money in my fridge" numbers are useless without them.
struct ItemPriceEditor: View {
    let item: PantryItemSnapshot
    let viewModel: MoneyInFridgeViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var totalPaidText = ""
    @State private var hasExpiry = false
    @State private var expiryDate = Date()
    @State private var error: String?

    private var quantityString: String {
        item.quantity == item.quantity.rounded() ? String(Int(item.quantity)) : String(item.quantity)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(viewModel.currency.symbol).foregroundStyle(.secondary)
                        TextField("What you paid", text: $totalPaidText)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("funds.price.total")
                    }
                } header: {
                    Text("Price")
                } footer: {
                    Text("For the \(quantityString) \(item.unit) you have now. Leave it empty if you don't know.")
                }

                Section("Expiry") {
                    Toggle("Has an expiry date", isOn: $hasExpiry)
                        .accessibilityIdentifier("funds.price.hasExpiry")
                    if hasExpiry {
                        DatePicker("Expires", selection: $expiryDate, displayedComponents: .date)
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("funds.price.save")
                }
            }
            .onAppear(perform: prefill)
        }
    }

    // show what's already saved, as a total rather than per unit
    private func prefill() {
        if let total = item.lineValue {
            // per-unit cost x quantity can come back as 9.9999..., so round it for the field
            totalPaidText = String(format: "%.2f", NSDecimalNumber(decimal: total.amount).doubleValue)
        }
        if let expiry = viewModel.priceInfo(for: item)?.expiryDate {
            hasExpiry = true
            expiryDate = expiry
        }
    }

    private func save() {
        error = viewModel.savePrice(for: item, totalPaidText: totalPaidText, expiryDate: hasExpiry ? expiryDate : nil)
        if error == nil { dismiss() }
    }
}
