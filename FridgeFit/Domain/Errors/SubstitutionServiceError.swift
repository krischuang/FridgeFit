//
//  SubstitutionServiceError.swift
//  FridgeFit
//

import Foundation

/// Every way asking a `SubstitutionService` for suggestions can fail.
/// Messages are written for the user - raw networking/provider errors
/// never reach the UI directly.
enum SubstitutionServiceError: LocalizedError, Equatable {
    /// No OpenRouter API key configured locally - see Secrets.xcconfig.example.
    case notConfigured
    /// Reached the provider, but it returned an error (bad request,
    /// server error, etc).
    case providerUnavailable
    /// Hit the provider's rate limit.
    case rateLimited
    case network
    case timeout
    /// The provider's response couldn't be parsed into the expected
    /// suggestion schema.
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Substitution suggestions aren't set up yet. Add an OpenRouter API key to Secrets.xcconfig to enable this feature."
        case .providerUnavailable:
            return "The substitution service is temporarily unavailable. Please try again later."
        case .rateLimited:
            return "The substitution service is busy right now. Please try again in a moment."
        case .network:
            return "Couldn't reach the substitution service. Check your connection and try again."
        case .timeout:
            return "The substitution request timed out. Please try again."
        case .malformedResponse:
            return "The substitution service returned an unexpected response. Please try again."
        }
    }
}
