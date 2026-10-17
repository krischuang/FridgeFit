//
//  SubstitutionService.swift
//  FridgeFit
//

import Foundation

/// Abstraction over whatever suggests substitutions - an LLM provider
/// today, something else later.
///
/// Returns untrusted `RawSubstitutionSuggestion`s only. Nothing about
/// pantry availability, quantities-on-hand, or feasibility ever comes from
/// here - `GetIngredientSubstitutionsUseCase` validates every suggestion
/// against the real pantry before it reaches the UI.
nonisolated protocol SubstitutionService {
    func suggestSubstitutions(for request: SubstitutionRequest) async throws -> [RawSubstitutionSuggestion]
}
