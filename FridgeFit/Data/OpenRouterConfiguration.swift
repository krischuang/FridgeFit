//
//  OpenRouterConfiguration.swift
//  FridgeFit
//

import Foundation

/// Local, non-committed configuration for `OpenRouterSubstitutionService`.
///
/// Values are read from Info.plist, which pulls `OPENROUTER_API_KEY` /
/// `OPENROUTER_MODEL` in from build settings - see Config.xcconfig and
/// Secrets.example.xcconfig. No key ever lives in source control.
struct OpenRouterConfiguration {
    let apiKey: String
    let model: String
    /// Optional attribution headers OpenRouter uses for its public
    /// leaderboards. Requests work fine without them.
    let referer: String?
    let appTitle: String?

    /// `nil` if no API key is configured locally - callers should fall
    /// back to a service that fails with `SubstitutionServiceError.notConfigured`
    /// rather than crash or silently send an empty key.
    static func loadFromInfoPlist(bundle: Bundle = .main) -> OpenRouterConfiguration? {
        guard
            let apiKey = bundle.object(forInfoDictionaryKey: "OPENROUTER_API_KEY") as? String,
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let configuredModel = (bundle.object(forInfoDictionaryKey: "OPENROUTER_MODEL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (configuredModel?.isEmpty == false ? configuredModel : nil) ?? "google/gemma-4-31b-it:free"

        return OpenRouterConfiguration(
            apiKey: apiKey,
            model: model,
            referer: "https://github.com/krischuang/FridgeFit",
            appTitle: "FridgeFit"
        )
    }
}
