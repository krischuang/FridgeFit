//
//  SubstitutionResponseParser.swift
//  FridgeFit
//

import Foundation

/// Parses a chat model's raw text output into `[RawSubstitutionSuggestion]`.
///
/// Even with strict JSON instructions in the prompt, some models wrap
/// their answer in a markdown code fence or add stray whitespace - this
/// strips that defensively before decoding, but never tries to repair
/// actually-malformed JSON. Any decoding failure becomes
/// `SubstitutionServiceError.malformedResponse`, never a crash or a
/// partially-trusted result.
nonisolated enum SubstitutionResponseParser {
    private struct SuggestionsPayload: Decodable {
        let suggestions: [RawSubstitutionSuggestion]
    }

    static func parseSuggestions(fromModelOutput content: String) throws -> [RawSubstitutionSuggestion] {
        guard let jsonData = extractJSONObject(from: content) else {
            throw SubstitutionServiceError.malformedResponse
        }
        do {
            return try JSONDecoder().decode(SuggestionsPayload.self, from: jsonData).suggestions
        } catch {
            throw SubstitutionServiceError.malformedResponse
        }
    }

    /// Strips a leading/trailing markdown code fence if present, then
    /// takes the substring between the first `{` and the last `}` - the
    /// smallest change that tolerates "```json\n{...}\n```" or a stray
    /// sentence before/after the JSON, without attempting to fix broken
    /// JSON itself.
    private static func extractJSONObject(from content: String) -> Data? {
        var trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            trimmed = trimmed.replacingOccurrences(of: "```json", with: "```")
            trimmed = trimmed.replacingOccurrences(of: "```", with: "")
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let firstBrace = trimmed.firstIndex(of: "{"), let lastBrace = trimmed.lastIndex(of: "}"), firstBrace <= lastBrace else {
            return nil
        }
        return String(trimmed[firstBrace...lastBrace]).data(using: .utf8)
    }
}
