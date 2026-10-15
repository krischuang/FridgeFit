import SwiftUI

// screen 3 - every ingredient shown as money, soonest-to-expire first, so the user
// sees which dollars are about to get thrown away. each item can be marked wasted.
struct MoneyInFridgeView: View {
    @State private var viewModel: MoneyInFridgeViewModel
    @State private var editingItem: PantryItemSnapshot?

    init(environment: FundsEnvironment) {
        _viewModel = State(initialValue: MoneyInFridgeViewModel(environment: environment))
    }

    var body: some View {
        List {
            if let valuation = viewModel.valuation {
                Section {
                    HStack {
                        summaryColumn(title: "Total value",
                                      value: valuation.totalValue.formatted(),
                                      tint: .primary,
                                      alignment: .leading)
                        Spacer()
                        summaryColumn(title: "At risk",
                                      value: valuation.atRiskValue.formatted(),
                                      tint: .red,
                                      alignment: .trailing)
                    }
                }
            }

            Section {
                if viewModel.items.isEmpty {
                    Text("Nothing in your pantry yet - add things in the Pantry tab and they'll show up here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.items) { item in
                    PantryValueRow(
                        item: item,
                        isWastedToday: viewModel.wastedTodayIDs.contains(item.id),
                        onMarkWasted: { viewModel.markWasted(item) }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { editingItem = item }
                    .accessibilityIdentifier("funds.item.\(item.name)")
                }
            } header: {
                Text("Ingredients")
            } footer: {
                Text("Tap an item to add what you paid for it and when it goes off.")
            }

            if let message = viewModel.actionMessage {
                Section {
                    Label(message,
                          systemImage: viewModel.actionWasError
                              ? "exclamationmark.triangle.fill"
                              : "checkmark.circle.fill")
                        .foregroundStyle(viewModel.actionWasError ? .orange : .green)
                }
            }
        }
        .navigationTitle("Money in My Fridge")
        .task { await viewModel.reload() }
        .refreshable { await viewModel.reload() }
        .sheet(item: $editingItem) { item in
            ItemPriceEditor(item: item, viewModel: viewModel)
        }
    }

    private func summaryColumn(title: String, value: String,
                               tint: Color, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3).bold().foregroundStyle(tint)
        }
    }
}

// one ingredient row: name, quantity, expiry, dollar value, waste button
private struct PantryValueRow: View {
    let item: PantryItemSnapshot
    let isWastedToday: Bool
    let onMarkWasted: () -> Void

    private var daysLabel: String? {
        guard let days = item.daysUntilExpiry() else { return nil }
        switch days {
        case ..<0: return "Expired"
        case 0: return "Expires today"
        case 1: return "1 day left"
        default: return "\(days) days left"
        }
    }

    private var isAtRisk: Bool {
        guard let days = item.daysUntilExpiry() else { return false }
        return days <= 3
    }

    private var quantityString: String {
        item.quantity == item.quantity.rounded()
            ? String(Int(item.quantity))
            : String(item.quantity)
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                HStack(spacing: 8) {
                    Text("\(quantityString) \(item.unit)")
                        .font(.caption).foregroundStyle(.secondary)
                    if let daysLabel {
                        Text(daysLabel)
                            .font(.caption)
                            .foregroundStyle(isAtRisk ? .red : .secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if let value = item.lineValue {
                    Text(value.formatted()).bold()
                } else {
                    Text("No price").font(.caption).foregroundStyle(.secondary)
                }

                if isWastedToday {
                    Text("Wasted")
                        .font(.caption2).bold()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                } else {
                    Button("Threw out", action: onMarkWasted)
                        .font(.caption)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        MoneyInFridgeView(environment: .sample())
    }
}
