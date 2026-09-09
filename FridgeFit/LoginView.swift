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
            VStack(spacing: 20) {
                Image(systemName: "refrigerator")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)

                Text("Welcome to FridgeFit")
                    .font(.title2)
                    .bold()

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }

                if let errorMessage = authViewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await authViewModel.signIn(email: email, password: password) }
                } label: {
                    if authViewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Log In")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)

                HStack {
                    VStack { Divider() }
                    Text("or").font(.footnote).foregroundStyle(.secondary)
                    VStack { Divider() }
                }

                GoogleSignInButton {
                    Task { await authViewModel.signInWithGoogle() }
                }
                .disabled(authViewModel.isLoading)

                Button("Don't have an account? Sign up") {
                    showRegister = true
                }
                .font(.footnote)
            }
            .padding()
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
