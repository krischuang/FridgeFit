//
//  SubstitutionServiceError.swift
//  FridgeFit
//

import Foundation

/// Every way asking a `SubstitutionService` for suggestions can fail.
/// Messages are written for the user - raw `FoundationModels` errors are
/// logged by the provider and mapped onto one of these before they reach the
/// UI.
///
/// The cases changed when substitutions moved from OpenRouter to the
/// on-device model: there is no API key to be missing, no HTTP status to
/// report and no network to be unreachable, so `notConfigured`,
/// `providerUnavailable` and `network` are gone. What replaces them is
/// `substitutionUnavailable`, which carries *why* the model can't run so the
/// UI can explain it - the same shape `ReceiptScanError` and
/// `RecipeSuggestionError` already use.
///
/// `timeout` survives the move, but it now means something FridgeFit
/// enforces itself: `AppleSubstitutionService` bounds how long an on-device
/// generation may take, because a request that never returns is worse for
/// the user than one that gives up.
nonisolated enum SubstitutionServiceError: LocalizedError, Equatable {
    /// Substitutions aren't available - carries the reason so the UI can
    /// explain.
    case substitutionUnavailable(AppleIntelligenceAvailability)
    /// The on-device model ran but its answer couldn't be used.
    case suggestionFailed
    /// The model declined to answer, or the request tripped its safety
    /// guardrails.
    case requestNotAllowed
    /// The model was asked for too much at once, or is busy.
    case modelBusy
    /// Generation ran past the time FridgeFit is willing to wait.
    case timeout

    var errorDescription: String? {
        switch self {
        case .substitutionUnavailable(let availability):
            return Self.unavailableExplanation(for: availability)
        case .suggestionFailed:
            return "FridgeFit couldn't come up with substitutes for this ingredient just now. Please try again."
        case .requestNotAllowed:
            return "FridgeFit couldn't suggest substitutes for this ingredient."
        case .modelBusy:
            return "Apple Intelligence is busy right now. Please try again in a moment."
        case .timeout:
            return "Finding substitutes took too long. Please try again."
        }
    }

    /// Substitution-specific wording for each unavailable reason.
    ///
    /// `AppleIntelligenceAvailability.unavailableExplanation` is shared by
    /// the receipt scanner and pantry recipe ideas, and tells the user they
    /// can "add ingredients to your pantry by hand" - sensible advice there,
    /// nonsense for a cook who asked what to use instead of cream. The
    /// shared enum stays untouched; the feature-specific sentence lives
    /// here, which is what its documentation asks callers to do.
    private static func unavailableExplanation(for availability: AppleIntelligenceAvailability) -> String {
        switch availability {
        case .available:
            // Not reachable through `AppleSubstitutionService`, which only
            // throws this case once availability has already failed. Worded
            // as a plain retry rather than a contradiction.
            return "Substitute suggestions aren't available right now. Please try again."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings to get substitute suggestions. You can still cook the recipe with your own swap."
        case .deviceNotSupported:
            return "This device can't suggest substitutes on-device. You can still cook the recipe with your own swap."
        case .modelNotReady:
            return "Apple Intelligence is still getting set up on this device. Try again in a few minutes."
        case .unavailableForUnknownReason:
            return "Substitute suggestions aren't available right now. You can still cook the recipe with your own swap."
        }
    }
}
