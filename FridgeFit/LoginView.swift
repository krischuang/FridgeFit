//
//  LoginView.swift
//  FridgeFit
//

import GoogleSignInSwift
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var showRegister = false

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && !authViewModel.isLoading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FridgeFitTheme.Spacing.xLarge) {
                    Image(systemName: "refrigerator")
                        .font(.system(size: 56))
                        .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                        .accessibilityHidden(true)

                    Text("Welcome to FridgeFit")
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
                    }

                    if let errorMessage = authViewModel.errorMessage {
                        Text(errorMessage)
                            .font(FridgeFitTheme.Typography.metadata)
                            .foregroundStyle(FridgeFitTheme.ColorToken.errorText)
                            .multilineTextAlignment(.center)
                            .padding(FridgeFitTheme.Spacing.medium)
                            .frame(maxWidth: .infinity)
                            .background(FridgeFitTheme.ColorToken.errorBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control))
                    }

                    Button {
                        Task { await authViewModel.signIn(email: email, password: password) }
                    } label: {
                        if authViewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Log In")
                        }
                    }
                    .buttonStyle(FridgeFitPrimaryButtonStyle())
                    .disabled(!canSubmit)

                    HStack {
                        Divider().overlay(FridgeFitTheme.ColorToken.border)
                        Text("or")
                            .font(FridgeFitTheme.Typography.metadata)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        Divider().overlay(FridgeFitTheme.ColorToken.border)
                    }

                    GoogleSignInButton {
                        Task { await authViewModel.signInWithGoogle() }
                    }
                    .disabled(authViewModel.isLoading)

                    Button("Don't have an account? Sign up") {
                        showRegister = true
                    }
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                }
                .padding(FridgeFitTheme.Spacing.xLarge)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
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
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
