//
//  OnlineRecipeDetailView.swift
//  FridgeFit
//

import SwiftUI

/// Full view of an online recipe: what you have vs. need to buy, any
/// intolerance warnings, and the method. Read-only - it never edits the
/// pantry or the bundled recipes.
struct OnlineRecipeDetailView: View {
    let match: OnlineRecipeMatch
    let intolerances: Set<FoodIntolerance>
    @ObservedObject var recipeViewModel: RecipeViewModel

    private var recipe: OnlineRecipe { match.recipe }

    var body: some View {
        List {
            Section {
                OnlineRecipeImage(url: recipe.imageURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
                    .listRowInsets(EdgeInsets())

                VStack(alignment: .leading, spacing: 8) {
                    Text(recipe.title)
                        .font(.title2.bold())
                    HStack(spacing: 14) {
                        if let minutes = recipe.readyInMinutes {
                            Label("\(minutes) min", systemImage: "clock")
                        }
                        if let servings = recipe.servings {
                            Label("\(servings) servings", systemImage: "person.2.fill")
                        }
                        if let score = recipe.healthScore {
                            Label("Health \(Int(score))", systemImage: "heart.fill")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if !recipe.diets.isEmpty {
                        Text(recipe.diets.map(\.capitalized).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if match.isFromCache {
                        Label("Saved from an earlier search", systemImage: "icloud.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if recipeViewModel.canSaveRecipes {
                Section {
                    if recipeViewModel.isSaved(onlineRecipeID: recipe.id) {
                        Label("Saved to Recipes", systemImage: "bookmark.fill")
                            .foregroundStyle(.tint)
                    } else {
                        Button {
                            Task { await recipeViewModel.saveOnlineRecipe(recipe) }
                        } label: {
                            HStack {
                                Label("Save to Recipes", systemImage: "bookmark")
                                Spacer()
                                if recipeViewModel.isSaving(onlineRecipeID: recipe.id) {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(recipeViewModel.isSaving(onlineRecipeID: recipe.id))
                    }
                    if let message = recipeViewModel.savedRecipeErrorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("Saved recipes appear on the Recipes tab, where FridgeFit checks them against your pantry like any other recipe.")
                }
            }

            if let summary = recipe.summary, !summary.isEmpty {
                Section("About") {
                    Text(summary)
                        .font(.subheadline)
                        .lineLimit(6)
                }
            }

            Section("Allergens") {
                if let contained = recipe.containsIntolerances {
                    if contained.isEmpty {
                        Label("No common allergens detected", systemImage: "checkmark.shield")
                            .foregroundStyle(.green)
                    } else {
                        Label(
                            "May contain: " + contained.map(\.displayName).sorted().joined(separator: ", "),
                            systemImage: "exclamationmark.shield"
                        )
                        .foregroundStyle(contained.isDisjoint(with: intolerances) ? Color.secondary : Color.red)
                    }
                } else {
                    Label("Couldn't verify allergens for this recipe", systemImage: "questionmark.diamond")
                        .foregroundStyle(.orange)
                }
            }
            .font(.subheadline)

            Section {
                ForEach(recipe.ingredients) { ingredient in
                    let missing = match.isMissing(ingredient)
                    HStack {
                        Image(systemName: missing ? "cart.badge.plus" : "checkmark.circle.fill")
                            .foregroundStyle(missing ? Color.orange : Color.green)
                        Text(ingredient.name.capitalized)
                        Spacer()
                        Text(ingredient.formattedQuantity)
                            .foregroundStyle(ingredient.quantityIsUncertain ? Color.orange : Color.secondary)
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("Ingredients")
            } footer: {
                Text("\(match.missedIngredients.count) to buy · matched by the recipe service against your pantry names, not quantities.")
            }

            Section("Instructions") {
                if recipe.steps.isEmpty {
                    Text("No step-by-step method available for this recipe.")
                        .foregroundStyle(.secondary)
                    if let source = recipe.sourceURL {
                        Link("Open the original recipe", destination: source)
                    }
                } else {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .fontWeight(.semibold)
                            Text(step)
                        }
                    }
                }
            }

            Section {
                if let source = recipe.sourceURL {
                    Link(destination: source) {
                        Label("Source: \(recipe.sourceName ?? source.host() ?? "original recipe")", systemImage: "safari")
                    }
                }
                Link(destination: URL(string: "https://spoonacular.com/food-api")!) {
                    Text("Recipe data powered by Spoonacular")
                        .font(.footnote)
                }
            }
        }
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { recipeViewModel.savedRecipeErrorMessage = nil }
    }
}
