//
//  PantryRecipeIdeasView.swift
//  FridgeFit
//

import SwiftUI

/// Recipe ideas generated on-device from what's in the pantry, presented as
/// a sheet from the Recipes tab.
///
/// Sits alongside the bundled recipe list rather than inside it - these are
/// suggestions, and they're labelled as such. Which ingredients a suggestion
/// is missing comes from the pantry check in
/// `SuggestRecipesFromPantryUseCase`, never from the model.
struct PantryRecipeIdeasView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: RecipeSuggestionViewModel

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.canSuggest {
                    unavailableContent
                } else if viewModel.isLoading {
                    ProgressView("Looking at your pantry…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableView {
                        Label("Couldn't Suggest Recipes", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again") {
                            Task { await viewModel.loadSuggestions() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(FridgeFitTheme.ColorToken.brandFill)
                    }
                } else if viewModel.suggestions.isEmpty {
                    ContentUnavailableView {
                        Label("No Ideas Yet", systemImage: "lightbulb")
                    } description: {
                        Text(viewModel.hasLoadedEmptyResult
                             ? "There isn't enough in your pantry to suggest a recipe yet. Add a few more ingredients and try again."
                             : "Generate ideas based on what's in your pantry right now.")
                    } actions: {
                        Button("Suggest Recipes") {
                            Task { await viewModel.loadSuggestions() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(FridgeFitTheme.ColorToken.brandFill)
                    }
                } else {
                    suggestionList
                }
            }
            .navigationTitle("Pantry Ideas")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        viewModel.cancel()
                        dismiss()
                    }
                }
            }
            .task {
                if viewModel.suggestions.isEmpty && viewModel.canSuggest {
                    await viewModel.loadSuggestions()
                }
            }
        }
    }

    @ViewBuilder
    private var suggestionList: some View {
        List {
            Section {
                ForEach(viewModel.suggestions) { suggestion in
                    SuggestionRow(suggestion: suggestion)
                }
            } footer: {
                Text("Suggested on-device by Apple Intelligence. Ingredient availability is checked against your pantry, not guessed.")
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await viewModel.loadSuggestions() }
    }

    @ViewBuilder
    private var unavailableContent: some View {
        let availability = viewModel.availability
        ContentUnavailableView {
            Label(availability.unavailableTitle ?? "Suggestions Unavailable", systemImage: "sparkles.slash")
        } description: {
            Text(availability.unavailableExplanation ?? "")
        } actions: {
            Button("Back to Recipes") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(FridgeFitTheme.ColorToken.brandFill)
        }
    }
}

private struct SuggestionRow: View {
    let suggestion: RecipeSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(suggestion.name)
                    .font(.headline)
                Spacer()
                if let time = suggestion.formattedPreparationTime {
                    Text(time)
                        .font(.caption)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                }
            }

            if suggestion.usesOnlyPantryIngredients {
                Label("Uses only what you have", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.successText)
            } else {
                Label(
                    "Missing: \(suggestion.missingIngredients.joined(separator: ", "))",
                    systemImage: "cart"
                )
                .font(.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
            }

            Text("From your pantry: \(suggestion.availableIngredients.joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)

            Text(suggestion.shortInstructions)
                .font(.callout)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let pantry = InMemoryPantryRepository(seedItems: [
        PantryItem(ingredient: Ingredient(name: "Eggs", category: .other), quantity: 6, unit: .pieces),
        PantryItem(ingredient: Ingredient(name: "Tomato", category: .produce), quantity: 3, unit: .pieces)
    ])
    let service = MockRecipeSuggestionService(result: .success([
        RawRecipeSuggestion(
            name: "Tomato and egg scramble",
            requiredIngredients: ["Eggs", "Tomato", "Butter"],
            shortInstructions: "Beat the eggs. Soften the tomato in butter, then fold the eggs through until just set.",
            estimatedPreparationMinutes: 10
        )
    ]))
    return PantryRecipeIdeasView(
        viewModel: RecipeSuggestionViewModel(
            useCase: SuggestRecipesFromPantryUseCase(suggestionService: service, pantryRepository: pantry)
        )
    )
}
