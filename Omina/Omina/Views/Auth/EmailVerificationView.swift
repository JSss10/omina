// EmailVerificationView.swift
// Omina
//
// Nach der Registrierung: Das Konto wird mit dem Einmalcode aus der
// Bestätigungs-E-Mail verifiziert (alternativ funktioniert weiterhin der Link
// in der E-Mail). Aufbau nach Entwurf: Akzentleiste, Titel, darunter der
// Hinweis mit der verbleibenden Wartezeit, die Illustration und unten die
// einzige Aktion – die E-Mail erneut senden.
//
// Das Code-Feld schickt sich selbst ab, sobald alle Stellen getippt sind; es
// braucht deshalb keinen zweiten Button neben dem erneuten Senden.
//
// Die Illustration (Asset "MailboxCheck") folgt noch.

import SwiftUI

struct EmailVerificationView: View {
    @EnvironmentObject var authService: AuthService
    let email: String

    @State private var code = ""
    @State private var isVerifying = false
    @State private var isResending = false
    @State private var message: String?
    @State private var isError = false
    /// Restzeit, bis erneut gesendet werden darf.
    @State private var secondsUntilResend = Self.resendCooldown
    /// Erhöht sich mit jedem Versand und startet damit die Wartezeit neu.
    @State private var cooldownRun = 0

    /// Wartezeit zwischen zwei Sendungen (Entwurf: 45 Sekunden).
    private static let resendCooldown = 45

    private var canResend: Bool { secondsUntilResend == 0 && !isResending }

    private var subtitle: String {
        if secondsUntilResend > 0 {
            return "Du kannst die E-Mail in \(secondsUntilResend) Sekunden erneut senden."
        }
        return "Keine E-Mail von uns an \(email)? Sende sie dir noch einmal."
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandAccentBar()

            ScrollView {
                VStack(alignment: .leading, spacing: AppMetrics.Space.m) {
                    AuthHeader(title: "Checke deine Mailbox", subtitle: subtitle)

                    OTPCodeField(code: $code, length: AppConfig.emailOTPCodeLength) {
                        Task { await verify() }
                    }
                    .accessibilityLabel("Bestätigungscode, \(AppConfig.emailOTPCodeLength) Stellen")

                    if isVerifying {
                        HStack(spacing: AppMetrics.Space.s) {
                            ProgressView()
                                .tint(AppColor.accentPrimary)
                            Text("Code wird geprüft …")
                                .font(AppTypography.footnote)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }

                    if let message {
                        HStack(alignment: .top, spacing: AppMetrics.Space.s) {
                            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(isError ? AppColor.Status.blockedIcon : AppColor.Status.openIcon)
                            Text(message)
                                .foregroundStyle(isError ? AppColor.Status.blockedText : AppColor.Status.openText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(AppTypography.footnote)
                        .accessibilityElement(children: .combine)
                    }

                    AssetImage(name: "MailboxCheck", placeholderSymbol: "photo")
                        .frame(maxWidth: .infinity, minHeight: 260)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, AppMetrics.Space.l)
                .padding(.bottom, AppMetrics.Space.m)
            }
            .scrollDismissesKeyboard(.interactively)

            footer
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        // Läuft beim Erscheinen und startet nach jedem Versand neu.
        .task(id: cooldownRun) { await runCooldown() }
    }

    private var footer: some View {
        Button {
            Task { await resend() }
        } label: {
            if isResending {
                ProgressView()
                    .tint(AppColor.onAccent)
            } else {
                Text("E-Mail erneut senden")
            }
        }
        .buttonStyle(.appPrimary)
        .disabled(!canResend)
        .padding(.horizontal, AppMetrics.Space.l)
        .padding(.top, AppMetrics.Space.m)
        .padding(.bottom, AppMetrics.Space.s)
        .background(AppColor.backgroundPrimary)
    }

    // MARK: - Aktionen

    /// Zählt die Wartezeit sekundenweise herunter.
    private func runCooldown() async {
        while secondsUntilResend > 0 {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            secondsUntilResend -= 1
        }
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
        guard canResend else { return }
        isResending = true
        message = nil
        defer { isResending = false }

        do {
            try await authService.resendConfirmation(email: email)
            message = "E-Mail wurde erneut gesendet."
            isError = false
            secondsUntilResend = Self.resendCooldown
            cooldownRun += 1
        } catch {
            message = ErrorText.message(for: error, context: "Senden fehlgeschlagen")
            isError = true
        }
    }
}

#Preview {
    NavigationStack {
        EmailVerificationView(email: "name@beispiel.ch")
            .environmentObject(AuthService.shared)
    }
}