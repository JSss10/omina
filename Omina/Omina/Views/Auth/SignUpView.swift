// SignUpView.swift
// Omina
//
// Screen 0.2 – Konto erstellen. Aufbau nach Entwurf: Akzentleiste unter der
// Statusleiste, Titel und Einleitung, danach das Formular aus Feldern ohne
// eigene Label-Zeile (die Beschriftung steht im Feld). Vorname und Nachname
// teilen sich eine Zeile, ebenso Landesvorwahl und Telefonnummer. Ganz unten
// der rechtliche Hinweis und die beiden Aktionen «Zurück» und «Konto erstellen».
//
// Land und Telefonnummer sind freiwillig und landen – wie Vor- und Nachname –
// in den user_metadata des Supabase-Kontos; sie brauchen kein eigenes Feld im
// Profil-Schema.

import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var country: String = ""
    @State private var phone: String = ""
    @State private var password: String = ""
    @State private var passwordConfirm: String = ""

    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showVerification: Bool = false

    /// Feste Landesvorwahl: Der Feldtest läuft in der Schweiz, im Entwurf steht
    /// die Vorwahl deshalb als unveränderliches Feld vor der Nummer.
    private let dialCode = "+ 41"

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
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        isEmailValid &&
        isPasswordValid &&
        password == passwordConfirm
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandAccentBar()

            ScrollView {
                VStack(alignment: .leading, spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                    header
                    form
                    feedback
                    legalNotice
                }
                .padding(.horizontal, AppMetrics.Space.l)
                .padding(.bottom, AppMetrics.Space.m)
            }
            .scrollDismissesKeyboard(.interactively)

            actionBar
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        // Wie im Entwurf ohne Navigationsleiste – zurück geht es über die
        // Schaltfläche am unteren Rand.
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showVerification) {
            EmailVerificationView(email: email)
        }
    }

    // MARK: - Rahmen

    private var header: some View {
        VStack(alignment: .leading, spacing: AppMetrics.Space.s) {
            Text("Konto erstellen")
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColor.textBrand)
                .accessibilityAddTraits(.isHeader)

            Text("Mit einem Konto bleiben dein Profil und deine gespeicherten Orte auf all deinen Geräten erhalten.")
                .font(AppTypography.body)
                .foregroundStyle(AppColor.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, AppMetrics.Space.xxl + AppMetrics.Space.m)
        .padding(.bottom, AppMetrics.Space.l)
    }

    // MARK: - Formular

    private var form: some View {
        VStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
            HStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                AppTextField(
                    placeholder: "Vorname",
                    text: $firstName,
                    textContentType: .givenName,
                    autocapitalization: .words
                )
                AppTextField(
                    placeholder: "Nachname",
                    text: $lastName,
                    textContentType: .familyName,
                    autocapitalization: .words
                )
            }

            AppTextField(
                placeholder: "E-Mail",
                text: $email,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                autocapitalization: .never,
                autocorrection: false
            )

            AppTextField(
                placeholder: "Land",
                text: $country,
                textContentType: .countryName,
                autocapitalization: .words
            )

            HStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                Text(dialCode)
                    .font(AppTypography.body.weight(.semibold))
                    .foregroundStyle(AppColor.textBrand)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appFieldChrome()
                    .frame(width: 88)
                    .accessibilityLabel("Landesvorwahl \(dialCode)")

                AppTextField(
                    placeholder: "79 000 00 00",
                    text: $phone,
                    keyboardType: .phonePad,
                    textContentType: .telephoneNumber,
                    autocorrection: false
                )
            }

            AppTextField(
                placeholder: "Passwort",
                text: $password,
                textContentType: .newPassword,
                autocapitalization: .never,
                autocorrection: false,
                isSecure: true,
                showsRevealToggle: true
            )

            if !password.isEmpty {
                VStack(alignment: .leading, spacing: AppMetrics.Space.xs) {
                    passwordRule("Mindestens 8 Zeichen", fulfilled: hasMinLength)
                    passwordRule("Mindestens ein Buchstabe", fulfilled: hasLetter)
                    passwordRule("Mindestens eine Zahl", fulfilled: hasDigit)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppMetrics.Space.xs)
            }

            AppTextField(
                placeholder: "Passwort bestätigen",
                text: $passwordConfirm,
                textContentType: .newPassword,
                autocapitalization: .never,
                autocorrection: false,
                isSecure: true
            )
        }
    }

    /// Hinweise, die erst bei Bedarf erscheinen – der Entwurf zeigt das
    /// Formular im leeren Zustand.
    @ViewBuilder
    private var feedback: some View {
        if !passwordConfirm.isEmpty && !passwordsMatch {
            noticeRow("Die Passwörter stimmen nicht überein", symbol: "exclamationmark.triangle.fill")
        }

        if let errorMessage {
            noticeRow(errorMessage, symbol: "exclamationmark.triangle.fill")
        }
    }

    private var legalNotice: some View {
        Text("Mit dem Erstellen eines Kontos akzeptierst du den [Standard-Lizenzvertrag (EULA) von Apple](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/). Wie Omina deine Daten verarbeitet, steht in der Datenschutzerklärung in den Einstellungen.")
            .font(AppTypography.body)
            .foregroundStyle(AppColor.textSecondary)
            .tint(AppColor.accentPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, AppMetrics.Space.xxl)
    }

    private var actionBar: some View {
        HStack(spacing: AppMetrics.Space.m - AppMetrics.Space.xs) {
            Button {
                dismiss()
            } label: {
                NavigationActionLabel(title: "Zurück", direction: .back)
            }
            .buttonStyle(.appSecondary(fullWidth: true))

            Button {
                Task { await handleSignUp() }
            } label: {
                if isLoading {
                    ProgressView()
                        .tint(AppColor.onAccent)
                } else {
                    NavigationActionLabel(title: "Konto erstellen")
                }
            }
            .buttonStyle(.appPrimary(fullWidth: true))
            .disabled(!isFormValid || isLoading)
        }
        .padding(.horizontal, AppMetrics.Space.l)
        .padding(.top, AppMetrics.Space.m)
        .padding(.bottom, AppMetrics.Space.s)
        .background(AppColor.backgroundPrimary)
    }

    // MARK: - Bausteine

    /// Eine Zeile der Passwort-Checkliste (Häkchen = Regel erfüllt).
    private func passwordRule(_ text: String, fulfilled: Bool) -> some View {
        HStack(spacing: AppMetrics.Space.s) {
            Image(systemName: fulfilled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(fulfilled ? AppColor.Status.openIcon : AppColor.textSecondary)
            Text(text)
                .foregroundStyle(fulfilled ? AppColor.Status.openText : AppColor.textSecondary)
        }
        .font(AppTypography.footnote)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text): \(fulfilled ? "erfüllt" : "nicht erfüllt")")
    }

    private func noticeRow(_ text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: AppMetrics.Space.s) {
            Image(systemName: symbol)
                .foregroundStyle(AppColor.Status.blockedIcon)
            Text(text)
                .foregroundStyle(AppColor.Status.blockedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(AppTypography.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, AppMetrics.Space.xs)
        .accessibilityElement(children: .combine)
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
                lastName: lastName,
                country: country,
                phone: phone.isEmpty ? "" : "\(dialCode.replacingOccurrences(of: " ", with: ""))\(phone)"
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