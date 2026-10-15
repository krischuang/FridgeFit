//
//  OnlineRecipeSearchError.swift
//  FridgeFit
//

import Foundation

/// Every way finding online recipes can fail. Messages are written for the
/// user - raw networking/provider errors never reach the UI directly.
nonisolated enum OnlineRecipeSearchError: LocalizedError, Equatable {
    /// No Spoonacular API key configured locally - see Secrets.xcconfig.example.
    case notConfigured
    /// The pantry is empty, so there's nothing to search with.
    case emptyPantry
    /// The pantry couldn't be loaded.
    case pantryUnavailable
    /// The provider rejected the API key (HTTP 401).
    case unauthorized
    /// The daily quota is used up (HTTP 402) or requests are throttled (429).
    case quotaExceeded
    case providerUnavailable
    case network
    case timeout
    case malformedResponse
    /// The search worked but nothing matched (possibly after safety filtering).
    case noResults

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Online recipes aren't set up yet. Add a Spoonacular API key to Secrets.xcconfig to enable this feature."
        case .emptyPantry:
            return "Your pantry is empty. Add a few ingredients first so we know what to search for."
        case .pantryUnavailable:
            return "Couldn't load your pantry. Please try again."
        case .unauthorized:
            return "The recipe service rejected the API key. Check SPOONACULAR_API_KEY in Secrets.xcconfig."
        case .quotaExceeded:
            return "Today's recipe search limit has been reached. Please try again tomorrow."
        case .providerUnavailable:
            return "The recipe service is temporarily unavailable. Please try again later."
        case .network:
            return "Couldn't reach the recipe service. Check your connection and try again."
        case .timeout:
            return "The recipe search timed out. Please try again."
        case .malformedResponse:
            return "The recipe service returned an unexpected response. Please try again."
        case .noResults:
            return "No recipes matched your pantry and filters. Try loosening a filter or adding more ingredients."
        }
    }

    /// Whether this means "couldn't reach the server" - the only case where
    /// serving cached results is honest. Configuration or protocol problems
    /// must surface, not be papered over with old data.
    var isConnectivityFailure: Bool {
        switch self {
        case .network, .timeout: return true
        default: return false
        }
    }
}
