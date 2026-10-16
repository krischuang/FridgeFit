//
//  SpendHistoryView.swift
//  FridgeFit
//

import SwiftUI

// screen 4 - the record: total lost to waste, then recent spends and recent waste
struct SpendHistoryView: View {
    @State private var viewModel: SpendHistoryViewModel

    init(environment: FundsEnvironment) {
        _viewModel = State(initialValue: SpendHistoryViewModel(environment: environment))
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "trash.fill")
                        .foregroundStyle(.red)
                    Text("Wasted so far")
                    Spacer()
                    Text(viewModel.totalWasted.formatted())
                        .bold()
                        .foregroundStyle(.red)
                }
            }

            Section("Grocery spends") {
                if viewModel.spends.isEmpty {
                    Text("No spends logged yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.spends) { spend in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(spend.store ?? "Grocery spend")
                                Text(DateFormatting.string(spend.spentOn))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(spend.amount.formatted()).bold()
                        }
                    }
                }
            }

            Section("Wasted food") {
                if viewModel.wasteCosts.isEmpty {
                    Text("Nothing wasted — nice.").foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.wasteCosts) { cost in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cost.reason.displayName)
                                Text(DateFormatting.string(cost.discardedOn))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(cost.lostAmount.formatted())
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle("Spend & Waste")
        .task { await viewModel.reload() }
        .refreshable { await viewModel.reload() }
    }
}

#Preview {
    NavigationStack {
        SpendHistoryView(environment: .sample())
    }
}
