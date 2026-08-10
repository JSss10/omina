// NewPasswordView.swift
// Omina
//
// Neues Passwort setzen. Aufbau nach Entwurf: Akzentleiste, Titel mit
// Einleitung, das neue Passwort mit Stärkeanzeige darunter, die Wiederholung
// und am unteren Rand die Speichern-Aktion. Anders als bei der Registrierung
// trägt hier jedes Feld eine eigene Beschriftung darüber.
//
// Der Screen dient zwei Wegen: dem Ändern des Passworts aus den Einstellungen
// und – sobald der Wiederherstellungs-Link als Deep Link in die App führt –
// dem Zurücksetzen nach «Passwort vergessen». Beides läuft über dieselbe
// Supabase-Aktualisierung der angemeldeten Sitzung.

import SwiftUI

struct NewPasswordView: View {
    /// Aus den Einstellungen heraus bleibt die Navigationsleiste sichtbar,
    /// damit der Weg zurück offen ist. Im Wiederherstellungs-Flow steht der
    /// Screen wie im Entwurf ohne Leiste.
    var showsNavigationBar: Bool = false
    /// Zeigt unter der Hauptaktion einen Abbruch-Weg. Nötig, wenn der Screen
    /// nach dem Wiederherstellungs-Link ganzflächig über der App liegt und es
    /// sonst keinen Ausweg gäbe.
    var showsCancel: Bool = false

    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var password: String = ""
    @State private var passwordConfirm: String = ""
    @State private var isSaving = false
    @State private var message: String?
    @State private var isError = false

    private var strength: PasswordStrength { PasswordStrength.evaluate(password) }
    private var passwordsMatch: Bool { !passwordConfirm.isEmpty && password == passwordConfirm }
    private var isValid: Bool { strength.rawValue >= PasswordStrength.medium.rawValue && passwordsMatch }

    var body: some View {
        VStack(spacing: 0) {
            BrandAccentBar()

            ScrollView {
                VStack(alignment: .leading, spacing: AppMetrics.Space.xl) {
                    AuthHeader(
                        title: "Neues Passwort",
                        subtitle: "Mindestens 8 Zeichen, mit Zahl und Grossbuchstaben."
                    )

                    VStack(alignment: .leading, spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                        fieldLabel("Neues Passwort")

                        AppTextField(
                            placeholder: "Neues Passwort",
                            text: $password,
                            textContentType: .newPassword,
                            autocapitalization: .never,
                            autocorrection: false,
                            isSecure: true,
                            showsRevealToggle: true
                        )

                        PasswordStrengthBar(strength: strength)
                    }

                    VStack(alignment: .leading, spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                        fieldLabel("Passwort bestätigen")

                        AppTextField(
                            placeholder: "Passwort bestätigen",
                            text: $passwordConfirm,
                            textContentType: .newPassword,
                            autocapitalization: .never,
                            autocorrection: false,
                            isSecure: true
                        )

                        if !passwordConfirm.isEmpty && !passwordsMatch {
                            notice("Die Passwörter stimmen nicht überein", isError: true)
                        }
                    }

                    if let message {
                        notice(message, isError: isError)
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
        .toolbar(showsNavigationBar ? .visible : .hidden, for: .navigationBar)
        .navigationTitle(showsNavigationBar ? "Passwort ändern" : "")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.body)
            .foregroundStyle(AppColor.accentPrimary)
    }

    private func notice(_ text: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: AppMetrics.Space.s) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? AppColor.Status.blockedIcon : AppColor.Status.openIcon)
            Text(text)
                .foregroundStyle(isError ? AppColor.Status.blockedText : AppColor.Status.openText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(AppTypography.footnote)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(spacing: AppMetrics.Space.s) {
            Button {
                Task { await save() }
            } label: {
                if isSaving {
                    ProgressView()
                        .tint(AppColor.onAccent)
                } else {
                    Text("Neues Passwort speichern")
                }
            }
            .buttonStyle(.appPrimary)
            .disabled(!isValid || isSaving)

            if showsCancel {
                Button("Später") {
                    authService.finishPasswordRecovery()
                    dismiss()
                }
                .font(AppTypography.body)
                .foregroundStyle(AppColor.accentPrimary)
                .frame(maxWidth: .infinity, minHeight: AppMetrics.Touch.minimum)
                .disabled(isSaving)
            }
        }
        .padding(.horizontal, AppMetrics.Space.l)
        .padding(.top, AppMetrics.Space.m)
        .padding(.bottom, AppMetrics.Space.s)
        .background(AppColor.backgroundPrimary)
    }

    private func save() async {
        guard isValid, !isSaving else { return }
        isSaving = true
        message = nil
        defer { isSaving = false }

        do {
            try await authService.updatePassword(password)
            message = "Passwort gespeichert."
            isError = false
            // Beendet zugleich den Wiederherstellungs-Ablauf, falls der Screen
            // über den Link aus der E-Mail geöffnet wurde.
            authService.finishPasswordRecovery()
            dismiss()
        } catch {
            message = ErrorText.message(for: error, context: "Speichern fehlgeschlagen")
            isError = true
        }
    }
}

#Preview {
    NavigationStack {
        NewPasswordView()
            .environmentObject(AuthService.shared)
    }
}