//
//  RegisterView.swift
//  FridgeFit
//

import GoogleSignInSwift
import SwiftUI

/// Create account, in the Fresh Botanical redesign.
///
/// Same omissions as `LoginView` (no Apple provider, no invented community
/// figures), plus one of its own: the mock's "By signing up, you agree to our
/// Terms of Service & Privacy Policy" is left out because FridgeFit has
/// neither document to link to, and stating that someone agreed to a document
/// that does not exist is not a thing a sign-up screen may claim.
///
/// The confirm-password field the previous version had is also gone, which
/// the design intends: the password field reveals itself on request, so the
/// typo a second field guarded against is visible in the first one.
struct RegisterView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable {
        case fullName
        case email
        case password
    }

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordRevealed = false
    @FocusState private var focusedField: Field?

    /// The rule the design states under the field: at least 8 characters
    /// with at least one number. Firebase enforces 6, so this is the stricter
    /// of the two and the one the user is shown.
    private var validationError: String? {
        guard !password.isEmpty else { return nil }
        if password.count < 8 { return "Password must be at least 8 characters." }
        if !password.contains(where: \.isNumber) { return "Password must include at least 1 number." }
        return nil
    }

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && validationError == nil && !authViewModel.isLoading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FridgeFitTheme.Spacing.section) {
                    AuthBrandHeader(
                        title: "Create Account",
                        subtitle: "Join FridgeFit to track your pantry, rescue ingredients, and cook delicious meals."
                    )
                    .padding(.top, FridgeFitTheme.Spacing.large)

                    accountFields

                    if let errorMessage = authViewModel.errorMessage {
                        AuthMessageBanner(message: errorMessage, tone: .error)
                    }

                    createAccountButton

                    VStack(spacing: FridgeFitTheme.Spacing.medium) {
                        AuthDivider(title: "or sign up with")
                        googleButton
                    }

                    footer
                }
                .padding(.horizontal, FridgeFitTheme.Spacing.section)
                .padding(.bottom, FridgeFitTheme.Spacing.screen)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
            .navigationTitle("Sign Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FridgeFitTheme.ColorToken.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(FridgeFitTheme.ColorToken.primary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .disabled(authViewModel.isLoading)
                    .accessibilityLabel("Close sign up")
                }
            }
        }
    }

    private var accountFields: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.large) {
            AuthField(label: "Full Name", systemImage: "person", isFocused: focusedField == .fullName) {
                TextField("", text: $fullName, prompt: AuthFieldPrompt.text("Alex Morgan"))
                    .textContentType(.name)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .fullName)
                    .onSubmit { focusedField = .email }
            }

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

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
                AuthField(label: "Password", systemImage: "lock", isFocused: focusedField == .password) {
                    AuthPasswordEntry(
                        password: $password,
                        isRevealed: isPasswordRevealed,
                        placeholder: "Create a strong password",
                        textContentType: .newPassword,
                        onToggleReveal: { isPasswordRevealed.toggle() },
                        onSubmit: submit
                    )
                    .focused($focusedField, equals: .password)
                }

                Label(
                    validationError ?? "At least 8 characters with 1 number",
                    systemImage: validationError == nil ? "info.circle" : "exclamationmark.circle"
                )
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(
                    validationError == nil
                        ? FridgeFitTheme.ColorToken.textSecondary
                        : FridgeFitTheme.ColorToken.errorText
                )
                .padding(.horizontal, FridgeFitTheme.Spacing.xSmall)
            }
        }
    }

    private var createAccountButton: some View {
        Button(action: submit) {
            if authViewModel.isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: FridgeFitTheme.Spacing.small) {
                    Text("Create Account")
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(FridgeFitPrimaryButtonStyle(isPill: true))
        .disabled(!canSubmit)
        .accessibilityIdentifier("create-account")
    }

    /// Google's own button, for the reason `LoginView.googleButton` records.
    /// Signing up and signing in with Google are the same call: Firebase
    /// creates the account on first use.
    private var googleButton: some View {
        GoogleSignInButton(scheme: .light, style: .wide, state: .normal) {
            focusedField = nil
            Task {
                await authViewModel.signInWithGoogle()
                if authViewModel.isAuthenticated { dismiss() }
            }
        }
        .frame(height: 52)
        .disabled(authViewModel.isLoading)
    }

    private var footer: some View {
        HStack(spacing: FridgeFitTheme.Spacing.xSmall) {
            Text("Already have an account?")
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)

            Button("Sign In") { dismiss() }
                .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
        }
        .frame(maxWidth: .infinity)
    }

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil
        Task {
            await authViewModel.signUp(fullName: fullName, email: email, password: password)
            if authViewModel.isAuthenticated { dismiss() }
        }
    }
}

#Preview {
    RegisterView()
        .environmentObject(AuthViewModel(observesAuthState: false))
}
