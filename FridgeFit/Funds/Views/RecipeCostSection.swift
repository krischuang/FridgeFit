//
//  RecipeCostSection.swift
//  FridgeFit
//

import SwiftUI

// "Cost" section on the recipe detail screen: what you'd use from the pantry,
// what you'd still have to buy, per serving, and whether the shopping fits
// what's left of this week's budget. all from prices the user recorded.
struct RecipeCostSection: View {
    let recipe: Recipe

    @Environment(\.fundsEnvironment) private var environment
    @State private var estimate: RecipeCostEstimate?

    var body: some View {
        if let environment {
            Section {
                if let estimate {
                    content(estimate)
                } else {
                    ProgressView()
                }
            } header: {
                Text("Cost")
            } footer: {
                Text("Estimated from prices you've recorded - receipts, Add to Pantry and the Budget tab. Optional ingredients aren't counted.")
            }
            .task(id: recipe.id) {
                await environment.reload()
                estimate = environment.estimateRecipeCost.execute(recipe: recipe)
            }
        }
    }

    @ViewBuilder
    private func content(_ estimate: RecipeCostEstimate) -> some View {
        LabeledContent("From your pantry", value: "≈ \(estimate.fromPantry.formatted())")
            .accessibilityIdentifier("recipe.cost.fromPantry")
        LabeledContent("To buy", value: "≈ \(estimate.toBuy.formatted())")
            .accessibilityIdentifier("recipe.cost.toBuy")
        if let perServing = estimate.perServing {
            LabeledContent("Per serving", value: "≈ \(perServing.formatted())")
        }

        budgetRow(estimate)
            .accessibilityIdentifier("recipe.cost.budget")

        if !estimate.unpricedNames.isEmpty {
            Text("No price yet: \(estimate.unpricedNames.joined(separator: ", ")) - so the total is only partial.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("recipe.cost.unpriced")
        }

        DisclosureGroup("Breakdown") {
            ForEach(estimate.lines) { line in
                breakdownRow(line)
            }
        }
    }

    @ViewBuilder
    private func budgetRow(_ estimate: RecipeCostEstimate) -> some View {
        let period = estimate.budgetCadence == .fortnightly ? "fortnight" : "week"
        if let remaining = estimate.remainingBudget, let fits = estimate.fitsRemainingBudget {
            if !estimate.toBuy.isPositive {
                Label("Nothing to buy - uses what you've got", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if fits {
                Label("Fits this \(period)'s budget · \(remaining.formatted()) left", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                let over = Money(estimate.toBuy.amount - remaining.amount, remaining.currency)
                Label("\(over.formatted()) more than what's left this \(period)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } else {
            Label("Set a budget in the Budget tab to compare", systemImage: "chart.pie")
                .foregroundStyle(.secondary)
        }
    }

    private func breakdownRow(_ line: RecipeCostLine) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name)
                if line.role == .optional {
                    Text("optional, not counted")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let reason = line.unpricedReason {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
                if line.fromPantry.isPositive {
                    Text("have \(line.fromPantry.formatted())").font(.caption)
                }
                if line.toBuy.isPositive {
                    Text("buy \(line.toBuy.formatted())").font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
}
