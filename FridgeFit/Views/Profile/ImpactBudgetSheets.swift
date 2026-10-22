//
//  ImpactBudgetSheets.swift
//  FridgeFit
//
//  The three small editors Impact & Budget needs to be more than a read-only
//  screen: setting a food budget, logging a grocery spend, and putting a
//  price on an ingredient.
//
//  They are written in FridgeFit's own form idiom rather than ported from
//  the FridgeFunds branch's Budget tab, because that tab carries its own
//  navigation, cards and typography - none of which belong in Profile.
//

import SwiftUI

// MARK: - Budget

/// Creates or replaces the user's food budget.
struct BudgetSetupSheet: View {
    let existing: FoodBudget?
    let defaultCurrency: Currency
    let onSave: (Decimal, Currency, BudgetCadence, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var limitText: String
    @State private var currency: Currency
    @State private var cadence: BudgetCadence
    @State private var startDate: Date

    init(
        existing: FoodBudget?,
        defaultCurrency: Currency,
        onSave: @escaping (Decimal, Currency, BudgetCadence, Date) -> Void
    ) {
        self.existing = existing
        self.defaultCurrency = defaultCurrency
        self.onSave = onSave
        _limitText = State(initialValue: existing.map { "\($0.limit.amount)" } ?? "")
        _currency = State(initialValue: existing?.currency ?? defaultCurrency)
        _cadence = State(initialValue: existing?.cadence ?? .weekly)
        _startDate = State(initialValue: existing?.startDate ?? Date())
    }

    private var limit: Decimal? {
        DecimalInput.parse(limitText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Limit") {
                    HStack {
                        Text(verbatim: currency.symbol)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        TextField("0.00", text: $limitText)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Budget limit")
                    }
                    Picker("Currency", selection: $currency) {
                        ForEach(Currency.allCases, id: \.self) { option in
                            Text(verbatim: option.rawValue).tag(option)
                        }
                    }
                }

                Section("Period") {
                    Picker("Resets", selection: $cadence) {
                        ForEach(BudgetCadence.allCases, id: \.self) { option in
                            Text(verbatim: option.displayName).tag(option)
                        }
                    }
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                }

                Section {
                    Text("Spending is tracked against this limit for \(cadence.lengthInDays) days from the start date. Going over is reported, never blocked.")
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                }
            }
            .navigationTitle(existing == nil ? "Set food budget" : "Edit food budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let limit else { return }
                        onSave(limit, currency, cadence, startDate)
                        dismiss()
                    }
                    .disabled((limit ?? 0) <= 0)
                }
            }
        }
    }
}

// MARK: - Spend

/// Logs one grocery purchase against the active budget.
struct LogGrocerySpendSheet: View {
    let currency: Currency
    let onSave: (Decimal, Date, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var spentOn = Date()
    @State private var store = ""

    private var amount: Decimal? { DecimalInput.parse(amountText) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    HStack {
                        Text(verbatim: currency.symbol)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Spend amount")
                    }
                    DatePicker("Date", selection: $spentOn, in: ...Date(), displayedComponents: .date)
                }

                Section("Store") {
                    TextField("Optional", text: $store)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle("Log grocery spend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let amount else { return }
                        onSave(amount, spentOn, store)
                        dismiss()
                    }
                    .disabled((amount ?? 0) <= 0)
                }
            }
        }
    }
}

// MARK: - Item price

/// Records what one unit of an ingredient cost, so its value at risk can be
/// shown. Writes only to the FridgeFunds price store - the pantry item
/// itself is never modified from here.
///
/// Takes the three strings it actually renders rather than an
/// `AtRiskIngredient`. It used to take the model, which tied the only price
/// form in the app to the one screen that had such a value to hand - the
/// Impact screen's at-risk list - and that list only contains items expiring
/// within `ValueFridgeUseCase.atRiskWindowDays`. Pricing anything else was
/// therefore impossible, which is why fridge value could stay empty no
/// matter what the user did. My Fridge's ingredient drawer now opens the
/// same sheet for any item.
struct ItemPriceSheet: View {
    let itemName: String
    /// The pantry's own unit symbol, for the "price per ..." wording. Empty
    /// is tolerated and reads as "unit".
    let unit: String
    /// "200 g", for the explanatory line. `nil` omits that line.
    let quantityText: String?
    let currency: Currency
    /// The last price recorded for an ingredient with this name, if the
    /// price book has one.
    let suggestion: Money?
    let onSave: (Decimal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var costText = ""

    private var cost: Decimal? { DecimalInput.parse(costText) }

    private var unitLabel: String { unit.isEmpty ? "unit" : unit }

    var body: some View {
        NavigationStack {
            Form {
                Section("Price per \(unitLabel)") {
                    HStack {
                        Text(verbatim: currency.symbol)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        TextField("0.00", text: $costText)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Price per \(unitLabel)")
                    }
                    if let suggestion {
                        Button("Use last recorded price, \(suggestion.formatted())") {
                            costText = "\(suggestion.amount)"
                        }
                        .font(FridgeFitTheme.Typography.caption)
                    }
                }

                if let quantityText {
                    Section {
                        Text("You have \(quantityText) of \(itemName). Its value is this price multiplied by that amount.")
                            .font(FridgeFitTheme.Typography.caption)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    }
                }
            }
            .navigationTitle(itemName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let cost else { return }
                        onSave(cost)
                        dismiss()
                    }
                    .disabled((cost ?? 0) <= 0)
                }
            }
        }
    }
}
