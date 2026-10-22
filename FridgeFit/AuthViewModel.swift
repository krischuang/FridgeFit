//
//  AuthViewModel.swift
//  FridgeFit
//

import Combine
import Foundation
import FirebaseAuth
import GoogleSignIn
import UIKit

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var user: User?
    @Published var errorMessage: String?
    /// A completed action the user should hear about but that is not a
    /// failure, currently only "we sent the reset email". Kept separate from
    /// `errorMessage` so the two never have to share one label.
    @Published var infoMessage: String?
    @Published var isLoading = false

    var isAuthenticated: Bool { user != nil }

    private var authStateHandle: AuthStateDidChangeListenerHandle?

    init(observesAuthState: Bool = true) {
        guard observesAuthState else { return }

        let auth = Auth.auth()
        user = auth.currentUser
        authStateHandle = auth.addStateDidChangeListener { [weak self] _, user in
            self?.user = user
        }
    }

    deinit {
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        infoMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            user = result.user
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// - Parameter fullName: optional, and written to the Firebase profile's
    ///   `displayName` when given. `ProfileView.accountName` already prefers
    ///   that over the email's local part, so a name typed here is the name
    ///   shown there; leaving it blank keeps the existing fallback.
    func signUp(fullName: String = "", email: String, password: String) async {
        errorMessage = nil
        infoMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty {
                let request = result.user.createProfileChangeRequest()
                request.displayName = trimmedName
                // The account exists either way. A profile update that fails
                // must not read as a failed sign-up, so this is deliberately
                // not allowed to throw out of here.
                try? await request.commitChanges()
            }
            user = result.user
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sends Firebase's password reset email.
    ///
    /// Reports success for any syntactically valid address, including ones
    /// with no account: confirming which emails are registered would let
    /// anyone enumerate the user list from the sign-in screen.
    func sendPasswordReset(email: String) async {
        errorMessage = nil
        infoMessage = nil

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            errorMessage = "Enter your email address first, then tap Forgot Password."
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: trimmedEmail)
            infoMessage = "If an account exists for \(trimmedEmail), a reset link is on its way."
        } catch let error as NSError where error.code == AuthErrorCode.userNotFound.rawValue {
            infoMessage = "If an account exists for \(trimmedEmail), a reset link is on its way."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signInWithGoogle() async {
        errorMessage = nil
        infoMessage = nil
        isLoading = true
        defer { isLoading = false }

        guard let presentingViewController = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController
        else {
            errorMessage = "Unable to find a view to present Google Sign-In."
            return
        }

        do {
            let googleResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
            guard let idToken = googleResult.user.idToken?.tokenString else {
                errorMessage = "Google Sign-In did not return an ID token."
                return
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: googleResult.user.accessToken.tokenString
            )
            let authResult = try await Auth.auth().signIn(with: credential)
            user = authResult.user
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            user = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
