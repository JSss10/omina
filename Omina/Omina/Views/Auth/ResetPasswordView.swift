// ResetPasswordView.swift
// Omina
//
// Passwort-Zurücksetzen per E-Mail-Link (Supabase Auth). Wird als Sheet aus
// dem Login geöffnet.

import SwiftUI

struct ResetPasswordView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    
    @State private var email: String = ""
    @State private var isLoading: Bool = false
    @State private var message: String? = nil
    @State private var isError: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Wir senden dir einen Link zum Zurücksetzen deines Passworts.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                TextField("E-Mail", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                
                if let message = message {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(isError ? .red : .green)
                }
                
                Button {
                    Task { await handleReset() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    } else {
                        Text("Reset-Link senden")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                }
                .background(email.isEmpty ? Color.gray : Color.accentColor)
                .cornerRadius(12)
                .disabled(email.isEmpty || isLoading)
                
                Spacer()
            }
            .padding(24)
            .navigationTitle("Passwort vergessen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schliessen") { dismiss() }
                }
            }
        }
    }
    
    private func handleReset() async {
        isLoading = true
        message = nil
        defer { isLoading = false }
        
        do {
            try await authService.resetPassword(email: email)
            message = "E-Mail gesendet. Prüfe dein Postfach."
            isError = false
        } catch {
            message = "Fehler: \(error.localizedDescription)"
            isError = true
        }
    }
}

#Preview {
    NavigationStack {
        SignInView()
            .environmentObject(AuthService.shared)
    }
}
