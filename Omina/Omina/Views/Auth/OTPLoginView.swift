// OTPLoginView.swift
// Omina
//
// Anmeldung per Einmalcode (OTP): E-Mail eingeben, Einmalcode
// erhalten, Code eingeben – ganz ohne Passwort.

import SwiftUI

struct OTPLoginView: View {
    @EnvironmentObject var authService: AuthService

    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var isLoading = false
    @State private var message: String?
    @State private var isError = false

    private var isEmailValid: Bool {
        email.contains("@") && email.contains(".") && !email.contains(" ")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Mit Code anmelden")
                    .font(.largeTitle)
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 20)

                Text(codeSent
                     ? "Wir haben einen \(AppConfig.emailOTPCodeLength)-stelligen Code an \(email) geschickt."
                     : "Wir senden dir einen \(AppConfig.emailOTPCodeLength)-stelligen Einmalcode per E-Mail – kein Passwort nötig.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)

                if !codeSent {
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
                } else {
                    OTPCodeField(code: $code, length: AppConfig.emailOTPCodeLength) {
                        Task { await verifyCode() }
                    }
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(isError ? .red : .green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { codeSent ? await verifyCode() : await sendCode() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    } else {
                        Text(codeSent ? "Anmelden" : "Code senden")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                }
                .background(isActionEnabled ? Color.accentColor : Color.gray)
                .cornerRadius(12)
                .disabled(!isActionEnabled || isLoading)
                .padding(.top, 8)

                if codeSent {
                    Button("Code erneut senden") {
                        Task { await sendCode() }
                    }
                    .font(.subheadline)
                    .disabled(isLoading)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isActionEnabled: Bool {
        codeSent ? code.count == AppConfig.emailOTPCodeLength : isEmailValid
    }

    private func sendCode() async {
        isLoading = true
        message = nil
        defer { isLoading = false }

        do {
            try await authService.sendLoginCode(email: email)
            codeSent = true
            code = ""
            message = "Code gesendet. Prüfe dein Postfach."
            isError = false
        } catch {
            message = "Code konnte nicht gesendet werden. Prüfe die Adresse – für diese E-Mail muss bereits ein Konto bestehen."
            isError = true
        }
    }

    private func verifyCode() async {
        guard code.count == AppConfig.emailOTPCodeLength, !isLoading else { return }
        isLoading = true
        message = nil
        defer { isLoading = false }

        do {
            try await authService.verifyLoginCode(email: email, code: code)
        } catch {
            code = ""
            message = "Der Code ist ungültig oder abgelaufen. Bitte versuche es erneut."
            isError = true
        }
    }
}

#Preview {
    NavigationStack {
        OTPLoginView()
            .environmentObject(AuthService.shared)
    }
}