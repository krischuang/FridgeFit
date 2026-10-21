//
//  SubstitutionViewModel.swift
//  FridgeFit
//

import Combine
import Foundation

/// Presentation state for "Find Substitute" on a recipe detail screen.
///
/// A single recipe can have several unresolved ingredients at once, each
/// with its own independent "Find Substitute" button, so state is keyed
/// by `RecipeIngredient.id` rather than being one global loading/error
/// pair. Never computes or validates anything itself - that's all
/// `GetIngredientSubstitutionsUseCase`.
///
/// Now that the provider is the on-device model, this also owns two things
/// it didn't need against a hosted API: it reports `availability` so the UI
/// can explain itself instead of offering a button that always fails, and it
/// tracks the in-flight task per ingredient so leaving the screen cancels
/// generation rather than leaving the model working on an answer nobody will
/// read.
@MainActor
final class SubstitutionViewModel: ObservableObject {
    @Published private(set) var suggestionsByIngredient: [UUID: [SubstitutionSuggestion]] = [:]
    @Published private(set) var loadingIngredientIDs: Set<UUID> = []
    @Published private(set) var errorMessageByIngredient: [UUID: String] = [:]

    private let useCase: GetIngredientSubstitutionsUseCase
    private var tasksByIngredient: [UUID: Task<Void, Never>] = [:]

    init(useCase: GetIngredientSubstitutionsUseCase) {
        self.useCase = useCase
    }

    // No `deinit` on purpose, unlike `RecipeSuggestionViewModel`. The tasks
    // in `tasksByIngredient` capture `self` strongly, so this object cannot
    // be deallocated while any of them is still running - a cancel-on-deinit
    // would be unreachable code. Cancellation that matters comes from
    // `cancelAll()`, which `RecipeDetailView` calls on disappear.

    /// Whether substitutions can be generated right now. Read fresh: the
    /// user can turn Apple Intelligence on while this screen is open.
    var availability: AppleIntelligenceAvailability {
        useCase.availability
    }

    /// Whether "Find Substitute" should be offered at all.
    var canFindSubstitutes: Bool { availability.canScan }

    func findSubstitutes(for recipeIngredient: RecipeIngredient, recipe: Recipe, feasibility: RecipeFeasibilityResult) async {
        let ingredientID = recipeIngredient.id

        // Ignored while this ingredient already has a request in flight, so
        // a double tap can't start two generations - the on-device model
        // rejects concurrent requests, and the second tap would surface that
        // to the user as a failure.
        guard !loadingIngredientIDs.contains(ingredientID) else { return }

        let availability = self.availability
        guard availability.canScan else {
            errorMessageByIngredient[ingredientID] = SubstitutionServiceError
                .substitutionUnavailable(availability)
                .localizedDescription
            return
        }

        errorMessageByIngredient[ingredientID] = nil
        loadingIngredientIDs.insert(ingredientID)

        // Unstructured on purpose. The work has to outlive the `Task` the
        // button wraps this call in, so that `cancel(for:)` is what ends it
        // - and so the handle can be stored to cancel in the first place.
        let task = Task { [useCase] in
            defer {
                self.loadingIngredientIDs.remove(ingredientID)
                self.tasksByIngredient[ingredientID] = nil
            }

            do {
                let suggestions = try await useCase.execute(recipe: recipe, targetIngredient: recipeIngredient, feasibility: feasibility)
                // Cancelled while the answer was coming back: discard it
                // rather than publishing onto a screen the user has left.
                try Task.checkCancellation()
                self.suggestionsByIngredient[ingredientID] = suggestions
                if suggestions.isEmpty {
                    self.errorMessageByIngredient[ingredientID] = "No usable substitutions were found for \(recipeIngredient.ingredient.name)."
                }
            } catch is CancellationError {
                // The user left, or asked again. Nothing to report: no
                // results, and no error on a screen nobody is reading.
            } catch {
                self.errorMessageByIngredient[ingredientID] = error.localizedDescription
            }
        }
        tasksByIngredient[ingredientID] = task

        // Callers - including the tests - await completion, so this stays an
        // ordinary `async` method from the outside.
        await task.value
    }

    /// Cancels in-flight generation for one ingredient.
    func cancel(for recipeIngredient: RecipeIngredient) {
        let ingredientID = recipeIngredient.id
        tasksByIngredient[ingredientID]?.cancel()
        tasksByIngredient[ingredientID] = nil
        loadingIngredientIDs.remove(ingredientID)
    }

    /// Cancels every in-flight generation - called when the recipe detail
    /// screen goes away.
    func cancelAll() {
        for task in tasksByIngredient.values {
            task.cancel()
        }
        tasksByIngredient.removeAll()
        loadingIngredientIDs.removeAll()
    }

    func suggestions(for recipeIngredient: RecipeIngredient) -> [SubstitutionSuggestion]? {
        suggestionsByIngredient[recipeIngredient.id]
    }

    func isLoading(for recipeIngredient: RecipeIngredient) -> Bool {
        loadingIngredientIDs.contains(recipeIngredient.id)
    }

    func errorMessage(for recipeIngredient: RecipeIngredient) -> String? {
        errorMessageByIngredient[recipeIngredient.id]
    }
}
