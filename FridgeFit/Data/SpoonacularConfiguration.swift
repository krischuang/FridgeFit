//
//  SpoonacularConfiguration.swift
//  FridgeFit
//

import Foundation

/// Local, non-committed configuration for `SpoonacularRecipeService`.
///
/// Resolution order:
/// 1. The `SPOONACULAR_API_KEY` environment variable (Xcode scheme or CI).
/// 2. Info.plist, which pulls `SPOONACULAR_API_KEY` in from build settings -
///    see Config.xcconfig and Secrets.xcconfig.example.
///
/// No key ever lives in source control.
nonisolated struct SpoonacularConfiguration: Equatable {
    let apiKey: String

    /// `nil` if no key is configured - callers fall back to
    /// `UnconfiguredOnlineRecipeService` rather than crash or send an empty
    /// credential.
    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SpoonacularConfiguration? {
        if let key = sanitized(environment["SPOONACULAR_API_KEY"]) {
            return SpoonacularConfiguration(apiKey: key)
        }
        if let key = sanitized(bundle.object(forInfoDictionaryKey: "SPOONACULAR_API_KEY") as? String) {
            return SpoonacularConfiguration(apiKey: key)
        }
        return nil
    }

    /// Trims stray whitespace/newlines (an easy copy-paste mistake that turns
    /// into a confusing 401) and rejects empty or placeholder values,
    /// including an unexpanded `$(SPOONACULAR_API_KEY)`.
    static func sanitized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !trimmed.hasPrefix("$("),
              trimmed != "your-spoonacular-api-key-here"
        else { return nil }
        return trimmed
    }
}
