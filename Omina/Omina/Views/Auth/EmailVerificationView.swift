// EmailVerificationView.swift
// Omina
//
// Nach der Registrierung: Das Konto wird mit dem Einmalcode aus der
// Bestätigungs-E-Mail verifiziert (alternativ funktioniert weiterhin der
// Link in der E-Mail). Der Code kann erneut angefordert werden.

import SwiftUI

struct EmailVerificationView: View {
    @EnvironmentObject var authService: AuthService
    let email: String

    @State private var code = ""
    @State private var isVerifying = false
    @State private var isResending = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "envelope.circle.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(.tint)
                    .padding(.top, 40)

                Text("Bestätige deine E-Mail-Adresse")
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.center)

                Text("Wir haben einen \(AppConfig.emailOTPCodeLength)-stelligen Code an \(email) geschickt. Gib ihn hier ein – oder tippe auf den Link in der E-Mail.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                OTPCodeField(code: $code, length: AppConfig.emailOTPCodeLength) {
                    Task { await verify() }
                }
                .padding(.horizontal, 24)

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(isError ? .red : .green)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    Task { await verify() }
                } label: {
                    if isVerifying {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    } else {
                        Text("Bestätigen")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                }
                .background(code.count == AppConfig.emailOTPCodeLength ? Color.accentColor : Color.gray)
                .cornerRadius(12)
                .disabled(code.count != AppConfig.emailOTPCodeLength || isVerifying)
                .padding(.horizontal, 24)

                Button {
                    Task { await resend() }
                } label: {
                    if isResending {
                        ProgressView()
                    } else {
                        Text("Code erneut senden")
                            .font(.subheadline)
                    }
                }
                .disabled(isResending)
                .padding(.bottom, 40)
            }
        }
        .navigationBarBackButtonHidden(false)
    }

    private func verify() async {
        guard code.count == AppConfig.emailOTPCodeLength, !isVerifying else { return }
        isVerifying = true
        message = nil
        defer { isVerifying = false }

        do {
            try await authService.verifySignUpCode(email: email, code: code)
            // Bei Erfolg setzt AuthService isAuthenticated und die App
            // wechselt automatisch in den angemeldeten Zustand.
        } catch {
            code = ""
            message = "Der Code ist ungültig oder abgelaufen. Bitte versuche es erneut."
            isError = true
        }
    }

    private func resend() async {
        isResending = true
        message = nil
        defer { isResending = false }

        do {
            try await authService.resendConfirmation(email: email)
            message = "E-Mail wurde erneut gesendet. Prüfe dein Postfach."
            isError = false
        } catch {
            message = "Senden fehlgeschlagen: \(error.localizedDescription)"
            isError = true
        }
    }
}