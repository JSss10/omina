// SignInView.swift
// Omina
//
// Anmeldung mit E-Mail und Passwort

import SwiftUI

struct SignInView: View {
    @EnvironmentObject var authService: AuthService

    @State private var email: String = ""
    @State private var password: String = ""

    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    @State private var showResetPassword: Bool = false

    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Anmelden")
                    .font(.largeTitle)
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 20)
                
                Text("Melde dich mit deinem Konto an.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
                
                // E-Mail
                VStack(alignment: .leading, spacing: 6) {
                    Text("E-Mail")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("name@beispiel.ch", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
                
                // Passwort
                VStack(alignment: .leading, spacing: 6) {
                    Text("Passwort")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SecureField("••••••••", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                }
                
                // Passwort vergessen
                Button("Passwort vergessen?") {
                    showResetPassword = true
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .trailing)

                // Error
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Sign In Button
                Button {
                    Task { await handleSignIn() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    } else {
                        Text("Anmelden")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                }
                .background(isFormValid ? Color.accentColor : Color.gray)
                .cornerRadius(12)
                .disabled(!isFormValid || isLoading)
                .padding(.top, 8)

                // Alternative: Anmeldung per Einmalcode
                NavigationLink {
                    OTPLoginView()
                } label: {
                    Text("Mit E-Mail-Code anmelden")
                        .font(.subheadline)
                }
                .padding(.top, 4)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showResetPassword) {
            ResetPasswordView()
        }
    }

    private func handleSignIn() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authService.signIn(email: email, password: password)
        } catch {
            errorMessage = "Anmeldung fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
