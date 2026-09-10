//
//  RawSubstitutionSuggestion.swift
//  FridgeFit
//

import Foundation

/// One substitution candidate exactly as a `SubstitutionService` returned
/// it - untrusted input.
///
/// Deliberately excludes anything about pantry state: whether the
/// ingredient is actually in the pantry, how much, or whether the unit is
/// comparable are all things only `SubstitutionSuggestionValidator` may
/// decide, never the provider. `suggestedUnit` stays a raw string (not
/// `MeasurementUnit`) because the provider can't be trusted to only emit
/// one of our known unit symbols.
struct RawSubstitutionSuggestion: Codable, Equatable {
    let ingredientName: String
    let suggestedQuantity: Double?
    let suggestedUnit: String?
    let confidence: Double?
    let explanation: String
    let limitations: String?
}
