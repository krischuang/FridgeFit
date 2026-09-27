//
//  RecipeSuggestionViewModel.swift
//  FridgeFit
//

import Combine
import Foundation

/// Presentation state for "Ideas from Your Pantry".
///
/// Kept separate from `RecipeViewModel` on purpose: that view model owns the
/// bundled recipes and their deterministic feasibility verdicts, and mixing
/// generated suggestions into it would blur which of the two the UI is
/// showing. Nothing here affects whether a bundled recipe is makeable.
@MainActor
final class RecipeSuggestionViewModel: ObservableObject {
    @Published private(set) var suggestions: [RecipeSuggestion] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// Set when the pantry had nothing to work with, or the model had no
    /// usable ideas - an empty state rather than an error.
    @Published private(set) var hasLoadedEmptyResult = false

    private let useCase: SuggestRecipesFromPantryUseCase
    private var suggestionTask: Task<Void, Never>?
    private var currentToken = 0

    init(useCase: SuggestRecipesFromPantryUseCase) {
        self.useCase = useCase
    }

    /// `isolated` for the same reason as `IngredientScannerViewModel` - a
    /// `@MainActor` class's plain `deinit` traps if the last reference is
    /// released off the main thread.
    isolated deinit {
        suggestionTask?.cancel()
    }

    var availability: IngredientRecognitionAvailability {
        useCase.availability
    }

    var canSuggest: Bool { availability.canScan }

    /// Generates suggestions from the current pantry.
    ///
    /// Ignored while a request is already in flight, and a superseded
    /// request can't publish its results - same token rule as
    /// `IngredientScannerViewModel`.
    func loadSuggestions() async {
        guard !isLoading else { return }

        let availability = self.availability
        guard availability.canScan else {
            errorMessage = IngredientRecognitionError.recognitionUnavailable(availability).localizedDescription
            return
        }

        currentToken += 1
        let token = currentToken

        isLoading = true
        errorMessage = nil
        hasLoadedEmptyResult = false
        defer { if token == currentToken { isLoading = false } }

        do {
            let loaded = try await useCase.execute()
            guard token == currentToken else { return }
            suggestions = loaded
            hasLoadedEmptyResult = loaded.isEmpty
        } catch is CancellationError {
            return
        } catch {
            guard token == currentToken else { return }
            suggestions = []
            errorMessage = (error as? IngredientRecognitionError)?.localizedDescription
                ?? IngredientRecognitionError.recognitionFailed.localizedDescription
        }
    }

    func cancel() {
        suggestionTask?.cancel()
        suggestionTask = nil
        currentToken += 1
        isLoading = false
    }
}
