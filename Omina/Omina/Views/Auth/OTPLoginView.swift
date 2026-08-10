// OTPLoginView.swift
// Omina
//
// Anmeldung per Einmalcode: E-Mail eingeben, Code erhalten, Code eingeben –
// ganz ohne Passwort. Aufbau nach Entwurf: Akzentleiste, Titel mit Einleitung,
// die Stellen des Codes als getönte Kreise, darunter der Hinweis mit dem Link
// zum erneuten Senden.
//
// Die Fusszeile richtet sich nach dem Zustand: Während der Eingabe steht
// «Bestätigen» über der Tastatur, sonst «Zurück» und «Weiter» nebeneinander.

import SwiftUI

struct OTPLoginView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var isLoading = false
    @State private var message: String?
    @State private var isError = false
    /// Wird das Code-Feld gerade bearbeitet? Steuert die Fusszeile.
    @State private var isEnteringCode = false

    private var isEmailValid: Bool {
        email.contains("@") && email.contains(".") && !email.contains(" ")
    }

    private var isActionEnabled: Bool {
        codeSent ? code.count == AppConfig.emailOTPCodeLength : isEmailValid
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandAccentBar()

            ScrollView {
                VStack(alignment: .leading, spacing: AppMetrics.Space.l) {
                    AuthHeader(title: title, subtitle: subtitle)

                    if codeSent {
                        OTPCodeField(
                            code: $code,
                            length: AppConfig.emailOTPCodeLength,
                            onComplete: { Task { await verifyCode() } },
                            onFocusChange: { isEnteringCode = $0 }
                        )

                        resendRow
                    } else {
                        AppTextField(
                            placeholder: "E-Mail",
                            text: $email,
                            keyboardType: .emailAddress,
                            textContentType: .emailAddress,
                            autocapitalization: .never,
                            autocorrection: false
                        )
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

    private var title: String {
        codeSent ? "Code eingeben" : "Mit Code anmelden"
    }

    private var subtitle: String {
        codeSent
            ? "Wir haben dir einen \(AppConfig.emailOTPCodeLength)-stelligen Code an \(email) geschickt."
            : "Wir senden dir einen \(AppConfig.emailOTPCodeLength)-stelligen Einmalcode per E-Mail – kein Passwort nötig."
    }

    /// Hinweis mit dem Link zum erneuten Senden (Entwurf: Text, darunter der
    /// violette Link).
    private var resendRow: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
            Text("Keinen Code erhalten? Prüfe den Spam-Ordner.")
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Code erneut senden") {
                Task { await sendCode() }
            }
            .font(AppTypography.body)
            .foregroundStyle(AppColor.accentPrimary)
            .frame(minHeight: AppMetrics.Touch.minimum, alignment: .leading)
            .disabled(isLoading)
        }
    }

    // MARK: - Fusszeile

    /// Während der Code-Eingabe steht die Bestätigen-Aktion über der Tastatur;
    /// sonst führen «Zurück» und «Weiter» durch den Ablauf.
    @ViewBuilder
    private var footer: some View {
        if isEnteringCode {
            Button {
                Task { await verifyCode() }
            } label: {
                if isLoading {
                    ProgressView()
                        .tint(AppColor.onAccent)
                } else {
                    NavigationActionLabel(title: "Bestätigen")
                }
            }
            .buttonStyle(.appPrimary)
            .disabled(!isActionEnabled || isLoading)
            .padding(.horizontal, AppMetrics.Space.l)
            .padding(.top, AppMetrics.Space.m)
            .padding(.bottom, AppMetrics.Space.s)
            .background(AppColor.backgroundPrimary)
        } else {
            HStack(spacing: AppMetrics.Space.m - AppMetrics.Space.xs) {
                Button {
                    if codeSent {
                        // Zurück zur E-Mail-Eingabe statt gleich aus dem Screen.
                        codeSent = false
                        code = ""
                        message = nil
                    } else {
                        dismiss()
                    }
                } label: {
                    NavigationActionLabel(title: "Zurück", direction: .back)
                }
                .buttonStyle(.appSecondary(fullWidth: true))

                Button {
                    Task { codeSent ? await verifyCode() : await sendCode() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(AppColor.onAccent)
                    } else {
                        NavigationActionLabel(title: codeSent ? "Anmelden" : "Weiter")
                    }
                }
                .buttonStyle(.appPrimary(fullWidth: true))
                .disabled(!isActionEnabled || isLoading)
            }
            .padding(.horizontal, AppMetrics.Space.l)
            .padding(.top, AppMetrics.Space.m)
            .padding(.bottom, AppMetrics.Space.s)
            .background(AppColor.backgroundPrimary)
        }
    }

    // MARK: - Aktionen

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