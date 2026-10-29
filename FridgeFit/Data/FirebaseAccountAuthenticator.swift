//
//  FirebaseAccountAuthenticator.swift
//  FridgeFit
//

import FirebaseAuth
import Foundation
import GoogleSignIn
import OSLog
import UIKit

/// `AccountAuthenticating` over Firebase Auth and Google Sign-In.
///
/// ## Provider awareness is the point of this type
///
/// FridgeFit has two sign-in routes: email/password and Google. Firebase will
/// refuse to delete an account whose session is older than a few minutes
/// (`requiresRecentLogin`), and the proof it then wants depends on how the
/// account was created. Getting that wrong is not a cosmetic problem:
/// prompting a Google-only user for "your FridgeFit password" asks for a
/// credential that has never existed, so they cannot delete their account and
/// are told, in effect, that they have forgotten something they were never
/// given.
///
/// So `currentProviders` reads `User.providerData` and the UI asks for
/// whichever proof that account can actually supply. An account with both
/// providers linked can use either.
///
/// ## Why `other` exists
///
/// A provider this build does not implement reauthentication for (an Apple
/// or phone credential linked outside this app, say) maps to
/// `AccountAuthProvider.other`, and the flow stops with
/// `noSupportedReauthenticationMethod` rather than guessing. Telling the user
/// to contact support is a worse experience than an in-app delete and a
/// better one than a button that silently cannot work.
@MainActor
final class FirebaseAccountAuthenticator: AccountAuthenticating {
    private let auth: Auth
    private let logger = Logger(subsystem: "com.fridgefit.app", category: "AccountDeletion")

    init(auth: Auth = Auth.auth()) {
        self.auth = auth
    }

    var currentUID: String? { auth.currentUser?.uid }

    var currentEmail: String? { auth.currentUser?.email }

    var currentProviders: [AccountAuthProvider] {
        guard let user = auth.currentUser else { return [] }
        let mapped = user.providerData.map { Self.provider(forProviderID: $0.providerID) }
        // Deduplicated, and ordered so `password` is offered first when an
        // account has both: typing a password is a smaller interruption than
        // a round trip through Google's sheet.
        var seen: Set<AccountAuthProvider> = []
        return AccountAuthProvider.allCases.filter { candidate in
            mapped.contains(candidate) && seen.insert(candidate).inserted
        }
    }

    /// Maps Firebase's provider id strings onto FridgeFit's enum.
    ///
    /// The two literals are Firebase's documented, stable provider ids. They
    /// are written out rather than read from `EmailAuthProviderID` /
    /// `GoogleAuthProviderID` so this function depends on nothing but a
    /// string, which is what makes it testable without a signed-in user -
    /// `UserInfo` cannot be constructed in a test, and this is the only part
    /// of the mapping with any logic in it.
    static func provider(forProviderID id: String) -> AccountAuthProvider {
        switch id {
        case "password":
            return .password
        case "google.com":
            return .google
        default:
            return .other
        }
    }

    func reauthenticate(using method: ReauthenticationMethod) async throws {
        guard let user = auth.currentUser else {
            throw DeleteAccountError.notSignedIn
        }

        let credential: AuthCredential
        switch method {
        case .password(let password):
            guard let email = user.email, !email.isEmpty else {
                // A password was offered for an account that has no email
                // identity. Not a wrong password - a wrong method.
                throw DeleteAccountError.noSupportedReauthenticationMethod
            }
            credential = EmailAuthProvider.credential(withEmail: email, password: password)

        case .google:
            credential = try await googleCredential()
        }

        do {
            _ = try await user.reauthenticate(with: credential)
        } catch let error as NSError {
            throw Self.reauthenticationError(from: error)
        }
    }

    func deleteCurrentUser() async throws {
        guard let user = auth.currentUser else {
            throw DeleteAccountError.notSignedIn
        }

        do {
            try await user.delete()
        } catch let error as NSError where error.code == AuthErrorCode.requiresRecentLogin.rawValue {
            throw DeleteAccountError.reauthenticationRequired(currentProviders)
        } catch {
            logger.error("Account deletion failed: \(error.localizedDescription, privacy: .public)")
            throw DeleteAccountError.accountDeletionFailed(error.localizedDescription)
        }
    }

    func signOut() throws {
        try auth.signOut()
        GIDSignIn.sharedInstance.signOut()
    }

    // MARK: - Google

    /// Runs Google's sign-in sheet again and turns the result into a Firebase
    /// credential.
    private func googleCredential() async throws -> AuthCredential {
        guard let presenting = Self.presentingViewController() else {
            throw DeleteAccountError.reauthenticationFailed("no window was available to present Google Sign-In")
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)

            guard let idToken = result.user.idToken?.tokenString else {
                throw DeleteAccountError.reauthenticationFailed("Google Sign-In did not return an ID token")
            }

            return GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
        } catch let error as DeleteAccountError {
            throw error
        } catch {
            throw DeleteAccountError.reauthenticationFailed(error.localizedDescription)
        }
    }

    private static func presentingViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
    }

    // MARK: - Error mapping

    /// Collapses Firebase's reauthentication failures into the two the UI
    /// distinguishes: a wrong password, which is worth retrying in place, and
    /// everything else.
    ///
    /// Internal so every branch is testable from an `NSError`, which is how
    /// these arrive.
    static func reauthenticationError(from error: NSError) -> DeleteAccountError {
        switch error.code {
        case AuthErrorCode.wrongPassword.rawValue,
             AuthErrorCode.invalidCredential.rawValue:
            return .wrongPassword
        case AuthErrorCode.userMismatch.rawValue:
            return .reauthenticationFailed("that sign-in was for a different account")
        default:
            return .reauthenticationFailed(error.localizedDescription)
        }
    }
}
