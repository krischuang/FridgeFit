//
//  OnlineRecipeDetailView.swift
//  FridgeFit
//

import SwiftUI

/// Full view of an online recipe: what you have vs. need to buy, any
/// allergen findings, and the method. Read-only - it never edits the pantry
/// or the bundled recipes.
///
/// ## Allergen wording
///
/// The source branch rendered an empty finding as "No common allergens
/// detected" with a green shield. That reads as a clearance, and FridgeFit
/// cannot issue one: the finding comes from keyword matching over provider
/// ingredient *names*, with no brands, processing or "may contain"
/// information behind it. The wording below reports what was actually done -
/// a screen of the ingredient list - and says plainly that it is not a
/// safety check. See `RecipeIntoleranceAnalysis` and `FoodIntolerance`.
struct OnlineRecipeDetailView: View {
    let match: OnlineRecipeMatch
    let intolerances: Set<FoodIntolerance>
    @ObservedObject var recipeViewModel: RecipeViewModel
    /// Near-expiry / expired pantry items this recipe would use.
    var expiryUse: OnlineRecipeExpiryUse = .none

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

            if expiryUse != .none {
                Section("Use It Up") {
                    if expiryUse.usesUrgentIngredient {
                        ForEach(expiryUse.urgent, id: \.ingredientName) { use in
                            Label(
                                "\(use.ingredientName) expires \(OnlineRecipeExpiryPresentation.whenText(for: use))",
                                systemImage: "clock.badge.exclamationmark"
                            )
                            .foregroundStyle(OnlineRecipeExpiryPresentation.tint(for: use.urgency))
                        }
                    }
                    if expiryUse.usesExpiredIngredient {
                        Label(
                            "\(expiryUse.expired.joined(separator: ", ")) in your pantry has expired - check it before cooking.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.red)
                    }
                }
                .font(.subheadline)
            }

            saveSection

            if let summary = recipe.summary, !summary.isEmpty {
                Section("About") {
                    Text(summary)
                        .font(.subheadline)
                        .lineLimit(6)
                }
            }

            allergenSection

            Section {
                ForEach(recipe.ingredients) { ingredient in
                    let missing = match.isMissing(ingredient)
                    HStack {
                        Image(systemName: missing ? "cart.badge.plus" : "checkmark.circle.fill")
                            .foregroundStyle(missing ? Color.orange : Color.green)
                        Text(OnlineIngredientName.displayName(ingredient.name))
                        Spacer()
                        Text(ingredient.formattedQuantity)
                            .foregroundStyle(ingredient.quantityIsUncertain ? Color.orange : Color.secondary)
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("Ingredients")
            } footer: {
                Text("\(match.missedIngredients.count) to buy · matched by the recipe service against your pantry names, not quantities. Save this recipe to have FridgeFit check quantities against your pantry.")
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

    /// The save control, or an explanation of why saving is switched off.
    ///
    /// Never renders a button that cannot work: while saved-recipe storage
    /// is gated off there is no repository behind it, so the control is
    /// replaced by the reason rather than left to fail.
    @ViewBuilder
    private var saveSection: some View {
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
        } else if let explanation = recipeViewModel.savedRecipeUnavailableExplanation {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Saving isn't available yet", systemImage: "bookmark.slash")
                        .font(.subheadline.weight(.semibold))
                    Text(explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private var allergenSection: some View {
        Section {
            if let contained = recipe.containsIntolerances {
                if contained.isEmpty {
                    Label(
                        "None of the allergens FridgeFit screens for appear in this recipe's ingredient list.",
                        systemImage: "magnifyingglass"
                    )
                    .foregroundStyle(.secondary)
                } else {
                    Label(
                        "May contain: " + contained.map(\.displayName).sorted().joined(separator: ", "),
                        systemImage: "exclamationmark.shield"
                    )
                    .foregroundStyle(contained.isDisjoint(with: intolerances) ? Color.secondary : Color.red)
                }
            } else {
                Label("FridgeFit couldn't screen this recipe's ingredients.", systemImage: "questionmark.diamond")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Allergen screening")
        } footer: {
            Text("This is a keyword screen of the ingredient names the recipe service supplied, not a safety check. It knows nothing about brands, processing or shared equipment. If you have an allergy, read the packaging of everything you cook with.")
        }
        .font(.subheadline)
    }
}
