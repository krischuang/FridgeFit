//
//  SubstitutionService.swift
//  FridgeFit
//

import Foundation

/// Abstraction over whatever suggests substitutions - the on-device Apple
/// Intelligence model today, something else later.
///
/// Returns untrusted `RawSubstitutionSuggestion`s only. Nothing about
/// pantry availability, quantities-on-hand, or feasibility ever comes from
/// here - `GetIngredientSubstitutionsUseCase` validates every suggestion
/// against the real pantry before it reaches the UI.
nonisolated protocol SubstitutionService {
    /// Whether substitutions can be generated right now, in FridgeFit's
    /// terms.
    ///
    /// Read fresh on every access - the user can turn Apple Intelligence on
    /// or off, and the model can finish downloading, while the app is open.
    /// Mirrors `RecipeSuggestionService` and `ReceiptIngredientInterpreter`,
    /// so nothing above the data layer has to know which framework is behind
    /// a feature or import it.
    var availability: AppleIntelligenceAvailability { get }

    /// Suggests substitutes for the ingredient described by `request`.
    ///
    /// - Throws: `SubstitutionServiceError`, never a provider-specific error
    ///   type; `CancellationError` if the caller cancelled.
    func suggestSubstitutions(for request: SubstitutionRequest) async throws -> [RawSubstitutionSuggestion]
}
