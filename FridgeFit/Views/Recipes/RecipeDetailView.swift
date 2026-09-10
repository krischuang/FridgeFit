//
//  RecipeDetailView.swift
//  FridgeFit
//

import SwiftUI

/// Full recipe view: ingredients compared against the pantry, and the
/// steps to cook it.
struct RecipeDetailView: View {
    let recipe: Recipe
    @ObservedObject var viewModel: RecipeViewModel

    private var feasibility: RecipeFeasibilityResult? { viewModel.feasibility(for: recipe) }

    var body: some View {
        List {
            Section {
                Text(recipe.summary)
                if let servings = recipe.servings {
                    Label("\(servings) servings", systemImage: "person.2.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Feasibility") {
                if let feasibility {
                    HStack {
                        Image(systemName: feasibility.status.symbolName)
                            .foregroundStyle(feasibility.status.tint)
                        Text(feasibility.status.title)
                        Spacer()
                        Text("\(Int(feasibility.coveragePercentage))% pantry coverage")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                } else {
                    ProgressView()
                }
            }

            Section("Ingredients") {
                if let feasibility {
                    ForEach(feasibility.evaluatedIngredients) { evaluation in
                        RecipeIngredientRow(evaluation: evaluation)
                    }
                } else {
                    ProgressView()
                }
            }

            Section("Instructions") {
                ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .fontWeight(.semibold)
                        Text(step)
                    }
                }
            }
        }
        .navigationTitle(recipe.title)
        .task { await viewModel.evaluateIfNeeded(recipe) }
    }
}
