//
//  RecipeRecommendationsView.swift
//  FridgeFit
//

import SwiftUI

/// Ranked meal recommendations for the user's current pantry and chosen
/// cooking context.
///
/// ## Navigation
///
/// Pushed onto the Recipes tab's existing `NavigationStack` and opens no
/// stack of its own, so there is exactly one navigation bar - the same
/// invariant `MyKitchenView` follows in the Kitchen tab. Because it shares
/// that stack, tapping a recommendation pushes the *existing*
/// `RecipeDetailView` and the back button returns here with the list and
/// the session intact.
struct RecipeRecommendationsView: View {
    @ObservedObject var viewModel: RecommendationViewModel
    /// Passed through to the existing detail screen, which owns the
    /// feasibility cache. Shared with `RecipeListView` rather than
    /// duplicated, so a verdict shown here and there is the same object.
    @ObservedObject var recipeViewModel: RecipeViewModel
    @ObservedObject var substitutionViewModel: SubstitutionViewModel

    @State private var isPresentingPreferences = false
    @State private var reportingRecipe: Recipe?

    var body: some View {
        content
            .navigationTitle("Recommended")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingPreferences = true
                    } label: {
                        Label("Preferences", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .task {
                // Only on first appearance. Coming back from a recipe
                // detail must not silently re-rank the list the user was
                // reading.
                if !viewModel.hasRun {
                    await viewModel.generate()
                }
            }
            .onDisappear { viewModel.cancel() }
            .refreshable { await viewModel.regenerate() }
            .sheet(isPresented: $isPresentingPreferences) {
                CookingContextFormView(context: viewModel.draftContext) { updated in
                    viewModel.draftContext = updated
                    Task { await viewModel.generate() }
                }
            }
            .confirmationDialog(
                "Why not this one?",
                isPresented: Binding(
                    get: { reportingRecipe != nil },
                    set: { if !$0 { reportingRecipe = nil } }
                ),
                titleVisibility: .visible
            ) {
                ForEach(SessionRecipeFeedbackReason.allCases) { reason in
                    Button(reason.displayText) {
                        if let recipe = reportingRecipe {
                            Task { await viewModel.record(.reported(reason), for: recipe) }
                        }
                        reportingRecipe = nil
                    }
                }
                Button("Cancel", role: .cancel) { reportingRecipe = nil }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && !viewModel.hasRecommendations {
            ProgressView("Looking at your pantry\u{2026}")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.hasRecommendations {
            recommendationList
        } else if let failure = viewModel.failure {
            failureView(failure)
        } else if let message = viewModel.unexpectedErrorMessage {
            ContentUnavailableView {
                Label("Couldn't Recommend Meals", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await viewModel.regenerate() } }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label("No Recommendations Yet", systemImage: "sparkles")
            } description: {
                Text("Generate meal ideas ranked against what's in your pantry right now.")
            } actions: {
                Button("Recommend Meals") { Task { await viewModel.generate() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var recommendationList: some View {
        List {
            Section {
                ForEach(viewModel.recommendations) { recommendation in
                    NavigationLink {
                        RecipeDetailView(
                            recipe: recommendation.recipe,
                            viewModel: recipeViewModel,
                            substitutionViewModel: substitutionViewModel
                        )
                    } label: {
                        RecommendationRow(
                            recommendation: recommendation,
                            feedback: viewModel.feedback(for: recommendation.recipe)
                        )
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            Task { await viewModel.record(.skipped, for: recommendation.recipe) }
                        } label: {
                            Label("Skip", systemImage: "eye.slash")
                        }
                        .tint(.gray)

                        Button {
                            reportingRecipe = recommendation.recipe
                        } label: {
                            Label("Not for me", systemImage: "hand.thumbsdown")
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            Task { await viewModel.record(.saved, for: recommendation.recipe) }
                        } label: {
                            Label("Save", systemImage: "bookmark")
                        }
                        .tint(.accentColor)
                    }
                }
            } header: {
                headerText
            } footer: {
                Text("Ranked against your pantry using converted quantities, not ingredient names. Swipe a meal to save, skip, or say it's not for you - that only affects this session.")
            }

            if !viewModel.session.recordedFeedback.isEmpty {
                Section {
                    Button("Start a new session") {
                        Task { await viewModel.startNewSession() }
                    }
                } footer: {
                    Text("Clears this session's saves, skips, and reports. Nothing here is stored.")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var headerText: some View {
        let count = viewModel.recommendations.count
        let suffix = viewModel.appliedContext?.hasExpressedPreferences == true
            ? " \u{00B7} preferences applied"
            : ""
        return Text("\(count) meal\(count == 1 ? "" : "s")\(suffix)")
    }

    private func failureView(_ failure: RecommendationGenerationError) -> some View {
        ContentUnavailableView {
            Label(
                failure.errorDescription ?? "No Recommendations",
                systemImage: failure == .pantryNeedsIngredients ? "cabinet" : "sparkles"
            )
        } description: {
            Text(failure.recoverySuggestion ?? "")
        } actions: {
            if failure.isResolvedByAdjustingPreferences {
                Button("Adjust Preferences") { isPresentingPreferences = true }
                    .buttonStyle(.borderedProminent)
            } else if failure == .everyRecipeSkippedInSession {
                Button("Start a New Session") {
                    Task { await viewModel.startNewSession() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Try Again") { Task { await viewModel.regenerate() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview {
    let pantry = InMemoryPantryRepository(seedItems: [
        PantryItem(ingredient: Ingredient(name: "Rice", category: .grain), quantity: 600, unit: .grams),
        PantryItem(ingredient: Ingredient(name: "Black Beans", category: .other), quantity: 500, unit: .grams),
        PantryItem(
            ingredient: Ingredient(name: "Onion", category: .produce),
            quantity: 3,
            unit: .pieces,
            expiryDate: Calendar.current.date(byAdding: .day, value: 1, to: .now)
        ),
        PantryItem(ingredient: Ingredient(name: "Garlic", category: .produce), quantity: 4, unit: .pieces),
        PantryItem(ingredient: Ingredient(name: "Eggs", category: .other), quantity: 6, unit: .pieces),
    ])
    let recipes = BundledRecipeRepository()
    NavigationStack {
        RecipeRecommendationsView(
            viewModel: RecommendationViewModel(
                generateUseCase: GenerateContextAwareRecommendationsUseCase(
                    recipeRepository: recipes,
                    pantryRepository: pantry
                )
            ),
            recipeViewModel: RecipeViewModel(recipeRepository: recipes, pantryRepository: pantry),
            substitutionViewModel: SubstitutionViewModel(
                useCase: GetIngredientSubstitutionsUseCase(
                    substitutionService: MockSubstitutionService(),
                    pantryRepository: pantry,
                    cache: SubstitutionCache()
                )
            )
        )
    }
}
