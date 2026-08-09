// ResetPasswordView.swift
// Omina
//
// Passwort-Zurücksetzen per E-Mail-Link (Supabase Auth). Aufbau nach Entwurf:
// Akzentleiste, Titel mit Einleitung, ein einzelnes E-Mail-Feld und unten die
// beiden Aktionen «Zurück» und «Link senden». Wird aus der Anmeldung
// aufgerufen und kehrt über «Zurück» dorthin zurück.

import SwiftUI

struct ResetPasswordView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var email: String = ""
    @State private var isLoading: Bool = false
    @State private var message: String? = nil
    @State private var isError: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            BrandAccentBar()

            ScrollView {
                VStack(alignment: .leading, spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                    AuthHeader(
                        title: "Passwort vergessen?",
                        subtitle: "Wir senden dir einen Link zum Zurücksetzen."
                    )

                    AppTextField(
                        placeholder: "E-Mail",
                        text: $email,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        autocapitalization: .never,
                        autocorrection: false
                    )

                    if let message {
                        HStack(alignment: .top, spacing: AppMetrics.Space.s) {
                            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(isError ? AppColor.Status.blockedIcon : AppColor.Status.openIcon)
                            Text(message)
                                .foregroundStyle(isError ? AppColor.Status.blockedText : AppColor.Status.openText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(AppTypography.footnote)
                        .padding(.top, AppMetrics.Space.xs)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, AppMetrics.Space.l)
                .padding(.bottom, AppMetrics.Space.m)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            footer
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var footer: some View {
        HStack(spacing: AppMetrics.Space.m - AppMetrics.Space.xs) {
            Button {
                dismiss()
            } label: {
                NavigationActionLabel(title: "Zurück", direction: .back)
            }
            .buttonStyle(.appSecondary(fullWidth: true))

            Button {
                Task { await handleReset() }
            } label: {
                if isLoading {
                    ProgressView()
                        .tint(AppColor.onAccent)
                } else {
                    NavigationActionLabel(title: "Link senden")
                }
            }
            .buttonStyle(.appPrimary(fullWidth: true))
            .disabled(email.isEmpty || isLoading)
        }
        .padding(.horizontal, AppMetrics.Space.l)
        .padding(.top, AppMetrics.Space.m)
        .padding(.bottom, AppMetrics.Space.s)
        .background(AppColor.backgroundPrimary)
    }

    private func handleReset() async {
        isLoading = true
        message = nil
        defer { isLoading = false }

        do {
            try await authService.resetPassword(email: email)
            message = "E-Mail gesendet. Prüfe dein Postfach – der Link führt dich zurück in die App."
            isError = false
        } catch {
            message = "Senden fehlgeschlagen: \(error.localizedDescription)"
            isError = true
        }
    }
}

#Preview {
    NavigationStack {
        ResetPasswordView()
            .environmentObject(AuthService.shared)
    }
}