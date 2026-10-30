//
//  DeleteAccountError.swift
//  FridgeFit
//

import Foundation

/// Which identity provider an account can prove itself with.
///
/// Firebase reports provider ids as strings (`"password"`, `"google.com"`).
/// They are mapped onto this enum at the edge so nothing above the data layer
/// has to know Firebase's spelling, and so an unrecognised provider is an
/// explicit case rather than a string nobody handles.
nonisolated enum AccountAuthProvider: String, Equatable, Sendable, CaseIterable {
    /// Email and password, created in FridgeFit's own sign-up screen.
    case password
    /// Google Sign-In.
    case google
    /// A provider this build cannot reauthenticate with. Surfaced rather
    /// than ignored: asking a Google-only user for a FridgeFit password they
    /// have never had is worse than telling them the truth.
    case other

    /// How the user is asked to prove who they are.
    var reauthenticationPrompt: String {
        switch self {
        case .password:
            return "Enter your password to confirm."
        case .google:
            return "Sign in with Google again to confirm."
        case .other:
            return "This account signs in with a method FridgeFit can't re-confirm on this screen."
        }
    }
}

/// What the user chose to prove who they are with.
nonisolated enum ReauthenticationMethod: Equatable, Sendable {
    case password(String)
    case google
}

/// Every way deleting a FridgeFit account can fail.
///
/// ## Why the failures are this specific
///
/// Account deletion is the one irreversible thing in the app, and "something
/// went wrong" is the least useful thing it could say. Each case here maps to
/// a different state the user's data is actually in, and therefore to
/// different advice:
///
/// - `remoteDataDeletionFailed` - **nothing** has been deleted. The account
///   still works and still has all its data. Retrying is safe.
/// - `localDataDeletionFailed` - cloud data is gone, on-device data may be
///   partly gone, the account still exists. Retrying resumes.
/// - `accountDeletionFailed` - the data is gone but the login is not.
///   Retrying finishes the job, and this is the one case where *not*
///   retrying leaves a usable login over an empty account.
///
/// Every stage is idempotent, which is what makes "retry" the honest advice
/// in all three cases rather than a hope.
nonisolated enum DeleteAccountError: LocalizedError, Equatable {
    /// Nobody is signed in, so there is no account to delete.
    case notSignedIn
    /// Firebase requires a recent sign-in before it will delete an account.
    /// Carries the providers this particular account can use, so the UI asks
    /// for the right proof.
    case reauthenticationRequired([AccountAuthProvider])
    /// The password entered to confirm deletion was wrong.
    case wrongPassword
    /// Re-proving identity failed for some other reason.
    case reauthenticationFailed(String)
    /// This account's only provider is one this build cannot re-confirm.
    case noSupportedReauthenticationMethod
    /// Cloud data could not be removed. Nothing else has been attempted.
    case remoteDataDeletionFailed(String)
    /// On-device data could not be removed.
    case localDataDeletionFailed(String)
    /// The data is gone but the Firebase account itself was not deleted.
    case accountDeletionFailed(String)
    /// The deletion service could not be reached at all, so nothing was
    /// attempted. Distinct from a failure *during* deletion.
    case backendUnreachable(String)
    /// The request was sent but no verdict came back - a timeout, an
    /// unreadable reply, a 5xx. The job may well have completed.
    ///
    /// This case exists because the alternative is a guess, and both guesses
    /// are harmful: reporting success would tell a user they are gone when
    /// they may not be, and reporting failure would send them to retry a
    /// deletion that already finished.
    case deletionStatusUnknown(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You're not signed in, so there's no account to delete."
        case .reauthenticationRequired:
            return "For your security, FridgeFit needs you to confirm it's really you before deleting your account."
        case .wrongPassword:
            return "That password doesn't match this account. Try again."
        case .reauthenticationFailed(let reason):
            return "FridgeFit couldn't confirm it's you: \(reason)"
        case .noSupportedReauthenticationMethod:
            return """
                This account signs in with a method FridgeFit can't re-confirm in the app, \
                so it can't be deleted from here. Contact support and your account will be \
                removed for you.
                """
        case .remoteDataDeletionFailed:
            return """
                Your cloud data couldn't be deleted, so FridgeFit stopped and changed nothing. \
                Your account and all your data are still here. Check your connection and try \
                again.
                """
        case .localDataDeletionFailed:
            return """
                Your cloud data was deleted but the copy on this device wasn't. Your account \
                still exists - tap Delete Account again to finish.
                """
        case .accountDeletionFailed:
            return """
                Your FridgeFit data has been deleted, but the sign-in itself could not be \
                removed. Tap Delete Account again to finish removing it.
                """
        case .backendUnreachable:
            return """
                FridgeFit couldn't reach the account service, so nothing has been deleted. \
                Your account and all your data are still here. Check your connection and \
                try again.
                """
        case .deletionStatusUnknown:
            return """
                FridgeFit couldn't confirm whether your account was deleted. It may still \
                be in progress. Open this screen again in a moment to check - don't assume \
                either way.
                """
        }
    }

    /// Whether tapping the destructive button again is a sensible next step.
    ///
    /// Every case except the two that need different input from the user, or
    /// a different channel entirely.
    var isRetryable: Bool {
        switch self {
        case .remoteDataDeletionFailed, .localDataDeletionFailed, .accountDeletionFailed,
             .reauthenticationFailed, .wrongPassword, .backendUnreachable, .deletionStatusUnknown:
            return true
        case .notSignedIn, .noSupportedReauthenticationMethod, .reauthenticationRequired:
            return false
        }
    }

    /// Whether the user's data has already been removed at the point this was
    /// thrown. Drives the warning that stopping now leaves a working login
    /// over an empty account.
    var dataAlreadyDeleted: Bool {
        switch self {
        case .accountDeletionFailed:
            return true
        case .notSignedIn, .reauthenticationRequired, .wrongPassword, .reauthenticationFailed,
             .noSupportedReauthenticationMethod, .remoteDataDeletionFailed, .localDataDeletionFailed,
             .backendUnreachable, .deletionStatusUnknown:
            return false
        }
    }
}
