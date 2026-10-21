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
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            user = result.user
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signUp(email: String, password: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            user = result.user
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signInWithGoogle() async {
        errorMessage = nil
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
