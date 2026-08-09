// SignUpView.swift
// Omina
//
// Registrierung mit E-Mail, Passwort, Vor- und Nachname

import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var passwordConfirm: String = ""
    
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showVerification: Bool = false
    @State private var showPassword: Bool = false
    
    // Passwort-Regeln, live geprüft und unter dem Feld angezeigt.
    private var hasMinLength: Bool { password.count >= 8 }
    private var hasLetter: Bool { password.rangeOfCharacter(from: .letters) != nil }
    private var hasDigit: Bool { password.rangeOfCharacter(from: .decimalDigits) != nil }
    private var isPasswordValid: Bool { hasMinLength && hasLetter && hasDigit }
    private var passwordsMatch: Bool { !passwordConfirm.isEmpty && password == passwordConfirm }

    private var isEmailValid: Bool {
        email.contains("@") && email.contains(".") && !email.contains(" ")
    }

    private var isFormValid: Bool {
        !firstName.isEmpty &&
        !lastName.isEmpty &&
        isEmailValid &&
        isPasswordValid &&
        password == passwordConfirm
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Konto erstellen")
                    .font(.largeTitle)
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 20)
                
                Text("Erstelle ein Konto, um deine persönlichen Barriere-Einstellungen zu speichern.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
                
                // Vorname / Nachname
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Vorname")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Vorname", text: $firstName)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.givenName)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nachname")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Nachname", text: $lastName)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.familyName)
                    }
                }
                
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
                
                // Passwort (mit "zeigen"-Toggle, Wireframe 0.2)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Passwort")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Group {
                            if showPassword {
                                TextField("••••••••", text: $password)
                            } else {
                                SecureField("••••••••", text: $password)
                            }
                        }
                        .textContentType(.newPassword)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()

                        Button(showPassword ? "verbergen" : "zeigen") {
                            showPassword.toggle()
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(.systemGray4), lineWidth: 0.5)
                    )

                    // Live-Prüfung der Passwort-Regeln
                    if !password.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            passwordRule("Mindestens 8 Zeichen", fulfilled: hasMinLength)
                            passwordRule("Mindestens ein Buchstabe", fulfilled: hasLetter)
                            passwordRule("Mindestens eine Zahl", fulfilled: hasDigit)
                        }
                        .padding(.top, 2)
                    }
                }

                // Passwort bestätigen
                VStack(alignment: .leading, spacing: 6) {
                    Text("Passwort bestätigen")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SecureField("••••••••", text: $passwordConfirm)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.newPassword)

                    if !passwordConfirm.isEmpty && !passwordsMatch {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Passwörter stimmen nicht überein")
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                }
                
                // Error
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Sign Up Button
                Button {
                    Task { await handleSignUp() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    } else {
                        Text("Konto erstellen")
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

                // Rechtliches: Apples Standard-Lizenzvertrag (EULA) statt eigener Texte
                VStack(spacing: 4) {
                    Text("Mit dem Erstellen eines Kontos akzeptierst du den [Standard-Lizenzvertrag (EULA) von Apple](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/).")
                    NavigationLink("Datenschutzerklärung anzeigen") {
                        PrivacyView()
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showVerification) {
            EmailVerificationView(email: email)
        }
    }

    // Eine Zeile der Passwort-Checkliste (Häkchen = Regel erfüllt).
    private func passwordRule(_ text: String, fulfilled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: fulfilled ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundColor(fulfilled ? .green : .secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(fulfilled ? .green : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text): \(fulfilled ? "erfüllt" : "nicht erfüllt")")
    }

    private func handleSignUp() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            try await authService.signUp(
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName
            )
            // Wenn Email-Bestätigung deaktiviert ist, ist man direkt eingeloggt
            // Sonst muss man die E-Mail bestätigen
            if !authService.isAuthenticated {
                showVerification = true
            }
        } catch {
            errorMessage = "Registrierung fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        SignUpView()
            .environmentObject(AuthService.shared)
    }
}