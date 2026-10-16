//
//  BudgetDashboardView.swift
//  FridgeFit
//

import SwiftUI

// screen 1 - home. how much budget's left this period, what's left today, and how
// much money is sitting in (and at risk in) the fridge. shows a setup card instead
// if there's no budget yet.
struct BudgetDashboardView: View {
    @State private var viewModel: BudgetDashboardViewModel
    private let environment: FundsEnvironment

    init(environment: FundsEnvironment) {
        self.environment = environment
        _viewModel = State(initialValue: BudgetDashboardViewModel(environment: environment))
    }

    var body: some View {
        ScrollView {
            if viewModel.hasNoBudget {
                BudgetSetupCard(viewModel: viewModel)
                    .padding()
            } else if let status = viewModel.status {
                VStack(spacing: 24) {
                    ringSection(status)
                    DashboardStat(icon: "sun.max.fill",
                                  title: "Left to spend today",
                                  value: status.todayRemaining.formatted(),
                                  tint: .blue)
                    fridgeSection()
                    linksSection()
                }
                .padding()
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView("Couldn't load your budget",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(error))
                    .padding(.top, 60)
            } else {
                ProgressView()
                    .padding(.top, 80)
            }
        }
        .navigationTitle(periodTitle)
        .task { await viewModel.reload() }
        .refreshable { await viewModel.reload() }
    }

    // the other three FridgeFunds screens hang off the dashboard, since in FridgeFit
    // the whole module gets one tab instead of four
    private func linksSection() -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                LogSpendView(environment: environment)
            } label: {
                linkRow("Log a spend", icon: "plus.circle.fill", tint: .blue)
            }
            Divider().padding(.leading, 52)
            NavigationLink {
                MoneyInFridgeView(environment: environment)
            } label: {
                linkRow("Money in my fridge", icon: "refrigerator.fill", tint: .green)
            }
            Divider().padding(.leading, 52)
            NavigationLink {
                SpendHistoryView(environment: environment)
            } label: {
                linkRow("Spend & waste history", icon: "clock.fill", tint: .orange)
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func linkRow(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 32)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .contentShape(Rectangle())
    }

    private var periodTitle: String {
        viewModel.status?.budget.cadence == .fortnightly ? "This Fortnight" : "This Week"
    }

    private func ringSection(_ status: BudgetStatus) -> some View {
        let spent = NSDecimalNumber(decimal: status.totalSpent.amount).doubleValue
        let limit = NSDecimalNumber(decimal: status.budget.limit.amount).doubleValue
        let fraction = limit > 0 ? spent / limit : 0

        return VStack(spacing: 12) {
            BudgetRingView(
                fraction: fraction,
                centerTitle: status.remaining.formatted(),
                centerSubtitle: status.hasOverspent ? "over budget" : "left"
            )
            Text("\(status.totalSpent.formatted()) spent of \(status.budget.limit.formatted())")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if status.isProjectedToOverspend && !status.hasOverspent {
                Label("On track to go over at your current pace",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func fridgeSection() -> some View {
        if let valuation = viewModel.valuation {
            VStack(spacing: 12) {
                DashboardStat(icon: "dollarsign.circle.fill",
                              title: "Money in your fridge",
                              value: valuation.totalValue.formatted(),
                              tint: .green)

                DashboardStat(icon: "exclamationmark.triangle.fill",
                              title: "About to be wasted",
                              value: valuation.atRiskValue.formatted(),
                              subtitle: valuation.atRiskValue.isPositive
                                  ? "≈ \(valuation.atRiskPerDay.formatted())/day to use it up"
                                  : nil,
                              tint: .red)

                if valuation.unvaluedItemCount > 0 {
                    Text("\(valuation.unvaluedItemCount) item\(valuation.unvaluedItemCount == 1 ? "" : "s") have no price yet — add costs to include them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// first-run card - set a budget before anything else can be tracked
private struct BudgetSetupCard: View {
    let viewModel: BudgetDashboardViewModel

    @State private var amountText = ""
    @State private var cadence: BudgetCadence = .weekly
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set your food budget")
                .font(.title2).bold()
            Text("How much do you want to spend on food each period? We'll track it for you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Period", selection: $cadence) {
                Text("Weekly").tag(BudgetCadence.weekly)
                Text("Fortnightly").tag(BudgetCadence.fortnightly)
            }
            .pickerStyle(.segmented)

            HStack {
                Text("$").foregroundStyle(.secondary)
                TextField("e.g. 120", text: $amountText)
                    .keyboardType(.decimalPad)
            }
            .padding()
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }

            Button {
                submit()
            } label: {
                Text("Start tracking").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func submit() {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: trimmed), value > 0 else {
            error = "Enter a budget greater than zero."
            return
        }
        error = nil
        viewModel.createBudget(limit: value, cadence: cadence)
    }
}

#Preview {
    NavigationStack {
        BudgetDashboardView(environment: .sample())
    }
}
