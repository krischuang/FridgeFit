//
//  AuthEmailValidator.swift
//  FridgeFit
//

import Foundation

/// Decides whether a typed address is worth sending to Firebase.
///
/// ## Why bother, when Firebase validates anyway
///
/// Because the round trip is the problem. Submitting `alex@fridgefit` means
/// a network call, a spinner, and a generic failure banner, for a mistake
/// that is visible in the field. Catching it locally turns that into an
/// inline message next to the thing that is wrong.
///
/// ## Why it is deliberately permissive
///
/// This is **not** an attempt to implement RFC 5322. Over-strict client-side
/// email validation is a classic own goal - it rejects addresses that are
/// genuinely valid (plus-addressing, new TLDs, non-ASCII locals) and leaves
/// the user with no way to sign in at all. So this only rejects what is
/// unambiguously wrong: no `@`, nothing before it, nothing after it, no dot
/// in the domain, or whitespace anywhere. Everything else is Firebase's call,
/// and `AuthErrorMessage` handles `invalidEmail` if it disagrees.
nonisolated enum AuthEmailValidator {

    static func isValid(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else { return false }

        // Exactly one `@`. Two is never a valid address and is a common
        // paste error.
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }

        let local = parts[0]
        let domain = parts[1]
        guard !local.isEmpty, !domain.isEmpty else { return false }

        // A domain needs a dot with something either side of it.
        guard let dot = domain.lastIndex(of: "."),
              dot != domain.startIndex,
              domain.index(after: dot) != domain.endIndex
        else { return false }

        // No consecutive dots, and no leading or trailing dot on either part.
        guard !trimmed.contains(".."),
              !local.hasPrefix("."), !local.hasSuffix("."),
              !domain.hasPrefix(".")
        else { return false }

        return true
    }
}
