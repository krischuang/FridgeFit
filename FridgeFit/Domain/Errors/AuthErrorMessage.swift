//
//  AuthErrorMessage.swift
//  FridgeFit
//

import FirebaseAuth
import Foundation

/// Turns a Firebase Auth error into something worth putting on a sign-in
/// screen.
///
/// ## Why this exists
///
/// `AuthViewModel` used to assign `error.localizedDescription` straight into
/// `errorMessage`, for every failure, on all four of sign-in, sign-up,
/// password reset and Google. That is Firebase's wording, not FridgeFit's,
/// and it has three problems on a login screen:
///
/// 1. **It is not actionable.** "The password is invalid or the user does not
///    have a password" tells someone who mistyped their password to consider
///    whether they have one.
/// 2. **It leaks implementation.** Strings like "There is no user record
///    corresponding to this identifier" name Firebase's data model to
///    somebody who is trying to cook dinner.
/// 3. **It can leak whether an account exists.** `userNotFound` on sign-in
///    confirms which email addresses are registered, which is the same
///    enumeration risk `sendPasswordReset` already deliberately avoids. The
///    sign-in path now matches it: a wrong email and a wrong password give
///    the same answer.
///
/// Mapping is by `AuthErrorCode`, not by string matching, so it is
/// locale-independent and survives Firebase changing its copy.
nonisolated enum AuthErrorMessage {

    /// What to show the user for a failed authentication attempt.
    ///
    /// - Parameter error: the error Firebase threw.
    /// - Returns: FridgeFit's wording. Unrecognised codes fall back to a
    ///   generic retry rather than to Firebase's text, because an unknown
    ///   code is exactly the case where the underlying message is most
    ///   likely to be unsuitable.
    /// Google Sign-In's own error domain and its "the user dismissed the
    /// sheet" code.
    ///
    /// Spelled out rather than imported from `GoogleSignIn`, so this type -
    /// and its tests - stay independent of that SDK. The values are part of
    /// its public API.
    private static let googleSignInDomain = "com.google.GIDSignIn"
    private static let googleSignInCancelledCode = -5

    static func text(for error: Error) -> String {
        let nsError = error as NSError

        // Dismissing Google's sheet arrives here, not as an `AuthErrorCode`,
        // so it has to be matched before the Firebase mapping - otherwise it
        // falls through to the generic "something went wrong" and the user
        // is shown a red banner for having changed their mind.
        if nsError.domain == googleSignInDomain, nsError.code == googleSignInCancelledCode {
            return ""
        }

        let code = AuthErrorCode(rawValue: nsError.code)

        switch code {
        // --- Credentials ------------------------------------------------
        //
        // Deliberately one message for all three. Distinguishing "no such
        // account" from "wrong password" would let anyone test an email
        // address against the sign-in form and learn whether it is
        // registered.
        case .wrongPassword, .userNotFound, .invalidCredential:
            return "That email or password doesn't match an account. Check them and try again."

        case .invalidEmail:
            return "That doesn't look like a valid email address."

        case .userDisabled:
            return "This account has been disabled. Contact support if you think that's a mistake."

        // --- Sign-up ----------------------------------------------------
        case .emailAlreadyInUse:
            return "An account already exists for that email. Try signing in instead."

        case .weakPassword:
            return "That password is too easy to guess. Use at least 8 characters with a number."

        // --- Transient --------------------------------------------------
        case .networkError:
            return "FridgeFit couldn't reach the network. Check your connection and try again."

        case .tooManyRequests:
            return "Too many attempts. Wait a minute and try again."

        // --- Provider ---------------------------------------------------
        case .accountExistsWithDifferentCredential:
            return "You've signed up with that email using a different sign-in method. Use that one instead."

        case .credentialAlreadyInUse:
            return "That sign-in is already linked to another FridgeFit account."

        case .requiresRecentLogin:
            return "For your security, sign in again before making this change."

        case .webContextCancelled:
            // The user backed out of a provider's web sheet. Not a failure,
            // and reporting it as one is noise.
            //
            // Google Sign-In's own cancellation arrives in its own error
            // domain rather than as an `AuthErrorCode`, so it is matched
            // separately in `isWorthReporting`.
            return ""

        default:
            return "Something went wrong signing you in. Please try again."
        }
    }

    /// Whether the failure is worth telling the user about at all.
    ///
    /// A cancelled provider sheet is the user's own decision, so showing a
    /// red banner for it would be reporting their own tap back at them.
    static func isWorthReporting(_ error: Error) -> Bool {
        !text(for: error).isEmpty
    }
}
