//
//  SpoonacularContentCleaner.swift
//  FridgeFit
//

import Foundation

/// Turns Spoonacular's raw text and image fields into something the app can
/// show as-is.
///
/// Spoonacular content is aggregated from many sites and is uneven. Every
/// rule here fixes a real class of bad result:
///
/// - **Steps:** `analyzedInstructions` is empty for many recipes whose
///   method lives only in the HTML `instructions` field. That field is now
///   used as a fallback, split on list items / line breaks, or on sentences
///   when it's one paragraph. Steps are stripped of HTML and leading
///   numbering ("1.", "Step 2:"), and fragments with no words are dropped.
/// - **Text:** titles, summaries and steps can carry HTML tags and entities,
///   including numeric ones (`&#8217;`). All are decoded.
/// - **Summary:** Spoonacular appends generated boilerplate ("spoonacular
///   score of 45%", "Try X for similar recipes"). Those sentences are
///   removed; the rest of the summary is kept verbatim.
/// - **Images:** `http://` URLs are blocked by App Transport Security, and
///   some results carry only a file name or only an `imageType`. These are
///   upgraded / completed against Spoonacular's own image CDN. Anything
///   unusable becomes `nil`, which the UI shows as a placeholder.
///
/// Nothing here invents content: a recipe with no method in either field
/// still has no steps, and the detail screen links to the original instead.
nonisolated enum SpoonacularContentCleaner {
    static let imageBaseURL = "https://img.spoonacular.com/recipes/"

    // MARK: - Title & summary

    static func title(_ raw: String) -> String {
        let cleaned = plainText(fromHTML: raw)
        return cleaned.isEmpty ? "Untitled recipe" : cleaned
    }

    /// Plain-text summary without Spoonacular's generated boilerplate, or
    /// `nil` if nothing meaningful is left.
    static func summary(fromHTML html: String) -> String? {
        let kept = sentences(in: plainText(fromHTML: html)).filter { sentence in
            let lower = sentence.lowercased()
            return !boilerplateMarkers.contains { lower.contains($0) }
        }
        let joined = kept.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    private static let boilerplateMarkers = [
        "spoonacular score",
        "similar recipe",
        "if you like this recipe",
        "you might also like",
        "found this recipe",
        "is liked by",
        "hit the spot",
        "brought to you by",
    ]

    // MARK: - Steps

    /// Cleaned steps from `analyzedInstructions`, falling back to the HTML
    /// `instructions` field when those are missing or unusable.
    static func steps(analyzed: [String], instructionsHTML: String?) -> [String] {
        let fromAnalyzed = tidySteps(analyzed.map(plainText(fromHTML:)))
        if !fromAnalyzed.isEmpty { return fromAnalyzed }

        guard let html = instructionsHTML,
              !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return [] }
        return tidySteps(stepsFromInstructionsHTML(html))
    }

    static func stepsFromInstructionsHTML(_ html: String) -> [String] {
        let separator = "\u{1F}"
        let marked = html.replacingOccurrences(
            of: "(?i)<li[^>]*>|<br\\s*/?>|</p>|\\r?\\n",
            with: separator,
            options: .regularExpression
        )
        var pieces = marked.components(separatedBy: separator)
            .map(plainText(fromHTML:))
            .filter { !$0.isEmpty }
        if pieces.count == 1 {
            pieces = sentences(in: pieces[0])
        }
        return pieces
    }

    static func tidySteps(_ steps: [String]) -> [String] {
        var result: [String] = []
        for step in steps {
            let stripped = step
                .replacingOccurrences(of: "(?i)^(step\\s*)?\\d+\\s*[.):]\\s+", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard stripped.count >= 3, stripped.contains(where: \.isLetter) else { continue }
            if let last = result.last, last.caseInsensitiveCompare(stripped) == .orderedSame { continue }
            result.append(stripped)
        }
        return result
    }

    // MARK: - Images

    static func imageURL(image: String?, imageType: String?, recipeID: Int) -> URL? {
        if let trimmed = image?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            let lower = trimmed.lowercased()
            let candidate: String
            if lower.hasPrefix("https://") {
                candidate = trimmed
            } else if lower.hasPrefix("http://") {
                candidate = "https://" + String(trimmed.dropFirst("http://".count))
            } else if trimmed.hasPrefix("//") {
                candidate = "https:" + trimmed
            } else {
                candidate = imageBaseURL + trimmed
            }
            if let url = URL(string: candidate), url.host != nil {
                return url
            }
        }
        if let type = imageType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !type.isEmpty, type.allSatisfy(\.isLetter) {
            return URL(string: "\(imageBaseURL)\(recipeID)-556x370.\(type)")
        }
        return nil
    }

    // MARK: - Text primitives

    /// Strips tags (keeping a space where a block ended), decodes entities,
    /// and collapses whitespace.
    static func plainText(fromHTML html: String) -> String {
        let spaced = html.replacingOccurrences(
            of: "(?i)<br\\s*/?>|</p>|</li>|</div>",
            with: " ",
            options: .regularExpression
        )
        let untagged = spaced.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeEntities(untagged)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func decodeEntities(_ text: String) -> String {
        var result = decodeNumericEntities(text)
        // `&amp;` last, so "&amp;lt;" becomes the literal text "&lt;", not "<".
        let named: [(String, String)] = [
            ("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"),
            ("&nbsp;", " "), ("&ndash;", "–"), ("&mdash;", "—"),
            ("&lsquo;", "‘"), ("&rsquo;", "’"), ("&ldquo;", "“"), ("&rdquo;", "”"),
            ("&hellip;", "…"), ("&deg;", "°"),
            ("&frac12;", "½"), ("&frac14;", "¼"), ("&frac34;", "¾"),
            ("&amp;", "&"),
        ]
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }

    private static func decodeNumericEntities(_ text: String) -> String {
        guard text.contains("&#"),
              let regex = try? NSRegularExpression(pattern: "&#([xX][0-9a-fA-F]+|[0-9]+);")
        else { return text }

        let source = text as NSString
        var output = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let body = source.substring(with: match.range(at: 1))
            let value: UInt32? = body.lowercased().hasPrefix("x")
                ? UInt32(body.dropFirst(), radix: 16)
                : UInt32(body)
            if let value, let scalar = Unicode.Scalar(value) {
                output.unicodeScalars.append(scalar)
            } else {
                output += source.substring(with: match.range)
            }
            cursor = match.range.location + match.range.length
        }
        output += source.substring(from: cursor)
        return output
    }

    /// Splits on ". ", "! ", "? " - not on decimals like "1.5".
    static func sentences(in text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            current.append(character)
            let isEnd = ".!?".contains(character)
                && index + 1 < characters.count
                && characters[index + 1] == " "
            if isEnd {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }
}
