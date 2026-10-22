//
//  LoginView.swift
//  FridgeFit
//

import GoogleSignInSwift
import SwiftUI

/// Sign in, in the Fresh Botanical redesign.
///
/// ## What the design file asked for and this screen does not do
///
/// - **No Sign in with Apple.** The mock shows one; it is deliberately left
///   out until there is an Apple identity provider behind it. A button that
///   cannot sign anyone in is worse than no button.
/// - **No community stat pill.** "32 ingredients rescued in your community
///   today" is a number FridgeFit does not have. Rendering it would be
///   presenting a made-up figure as a live one.
/// - **No "Protected by iCloud Sync" line.** FridgeFit syncs through Firebase,
///   not iCloud, so the line as written would be false. The trust line kept
///   below says only what the Firestore rules actually enforce.
struct LoginView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    private enum Field: Hashable {
        case email
        case password
    }

    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordRevealed = false
    @State private var showRegister = false
    @FocusState private var focusedField: Field?

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && !authViewModel.isLoading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FridgeFitTheme.Spacing.section) {
                    AuthBrandHeader(
                        title: "Welcome Back",
                        subtitle: "Sign in to access your pantry, saved recipes, and kitchen impact."
                    )
                    .padding(.top, FridgeFitTheme.Spacing.screen)

                    credentialFields

                    if let errorMessage = authViewModel.errorMessage {
                        AuthMessageBanner(message: errorMessage, tone: .error)
                    }

                    if let infoMessage = authViewModel.infoMessage {
                        AuthMessageBanner(message: infoMessage, tone: .confirmation)
                    }

                    signInButton

                    VStack(spacing: FridgeFitTheme.Spacing.medium) {
                        AuthDivider(title: "or continue with")
                        googleButton
                    }

                    footer
                }
                .padding(.horizontal, FridgeFitTheme.Spacing.section)
                .padding(.bottom, FridgeFitTheme.Spacing.screen)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
            .tint(FridgeFitTheme.ColorToken.primary)
            .sheet(isPresented: $showRegister) {
                RegisterView()
                    .environmentObject(authViewModel)
            }
        }
    }

    private var credentialFields: some View {
        VStack(spacing: FridgeFitTheme.Spacing.large) {
            AuthField(label: "Email Address", systemImage: "envelope", isFocused: focusedField == .email) {
                TextField("", text: $email, prompt: AuthFieldPrompt.text("alex@fridgefit.app"))
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }
            }

            AuthField(label: "Password", systemImage: "lock", isFocused: focusedField == .password) {
                AuthPasswordEntry(
                    password: $password,
                    isRevealed: isPasswordRevealed,
                    placeholder: "Your password",
                    textContentType: .password,
                    onToggleReveal: { isPasswordRevealed.toggle() },
                    onSubmit: submit
                )
                .focused($focusedField, equals: .password)
            } trailingLabel: {
                Button("Forgot Password?") {
                    focusedField = nil
                    Task { await authViewModel.sendPasswordReset(email: email) }
                }
                .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .disabled(authViewModel.isLoading)
            }
        }
    }

    private var signInButton: some View {
        Button(action: submit) {
            if authViewModel.isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: FridgeFitTheme.Spacing.small) {
                    Text("Sign In")
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(FridgeFitPrimaryButtonStyle(isPill: true))
        .disabled(!canSubmit)
        .accessibilityIdentifier("sign-in")
    }

    /// Google's own button rather than a restyled copy of it. The mock draws
    /// a white "Continue with Google" row; Google's branding terms govern how
    /// that button may look, and `GoogleSignInButton` is the version that
    /// stays compliant on its own.
    private var googleButton: some View {
        GoogleSignInButton(scheme: .light, style: .wide, state: .normal) {
            focusedField = nil
            Task { await authViewModel.signInWithGoogle() }
        }
        .frame(height: 52)
        .disabled(authViewModel.isLoading)
    }

    private var footer: some View {
        VStack(spacing: FridgeFitTheme.Spacing.large) {
            HStack(spacing: FridgeFitTheme.Spacing.xSmall) {
                Text("Don't have an account?")
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)

                Button("Sign Up") {
                    focusedField = nil
                    showRegister = true
                }
                .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
            }

            Label("Your pantry stays private to your FridgeFit account.", systemImage: "checkmark.shield")
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil
        Task { await authViewModel.signIn(email: email, password: password) }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel(observesAuthState: false))
}
