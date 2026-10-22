//
//  RegisterView.swift
//  FridgeFit
//

import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    private var validationError: String? {
        guard !password.isEmpty || !confirmPassword.isEmpty else { return nil }
        if password.count < 6 { return "Password must be at least 6 characters." }
        if password != confirmPassword { return "Passwords do not match." }
        return nil
    }

    private var canSubmit: Bool {
        !email.isEmpty && validationError == nil && !password.isEmpty && !authViewModel.isLoading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FridgeFitTheme.Spacing.xLarge) {
                    Text("Create Account")
                        .font(FridgeFitTheme.Typography.screenTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

                    VStack(spacing: FridgeFitTheme.Spacing.medium) {
                        TextField("Email", text: $email)
                            .textFieldStyle(FridgeFitTextFieldStyle())
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()

                        SecureField("Password", text: $password)
                            .textFieldStyle(FridgeFitTextFieldStyle())

                        SecureField("Confirm Password", text: $confirmPassword)
                            .textFieldStyle(FridgeFitTextFieldStyle())
                    }

                    if let validationError {
                        errorMessage(validationError)
                    }

                    if let message = authViewModel.errorMessage {
                        errorMessage(message)
                    }

                    Button {
                        Task {
                            await authViewModel.signUp(email: email, password: password)
                            if authViewModel.isAuthenticated { dismiss() }
                        }
                    } label: {
                        if authViewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Sign Up")
                        }
                    }
                    .buttonStyle(FridgeFitPrimaryButtonStyle())
                    .disabled(!canSubmit)
                }
                .padding(FridgeFitTheme.Spacing.xLarge)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
            .tint(FridgeFitTheme.ColorToken.primary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func errorMessage(_ message: String) -> some View {
        Text(message)
            .font(FridgeFitTheme.Typography.metadata)
            .foregroundStyle(FridgeFitTheme.ColorToken.errorText)
            .multilineTextAlignment(.center)
            .padding(FridgeFitTheme.Spacing.medium)
            .frame(maxWidth: .infinity)
            .background(FridgeFitTheme.ColorToken.errorBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control))
    }
}

#Preview {
    RegisterView()
        .environmentObject(AuthViewModel())
}
