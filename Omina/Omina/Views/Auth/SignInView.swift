// SignInView.swift
// Omina
//
// Anmeldung mit E-Mail und Passwort. Aufbau nach Entwurf: Akzentleiste, Titel
// mit Einleitung, die beiden Felder ohne eigene Label-Zeile, darunter die
// Hilfslinks und die Stadt-Illustration; «Anmelden» steht fix am unteren Rand.
//
// Die Illustration (Asset "SplashCity", dieselbe wie auf dem Startbild) folgt
// noch – bis dahin steht der Platzhalter an ihrer Stelle.

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
        VStack(spacing: 0) {
            BrandAccentBar()

            ScrollView {
                VStack(alignment: .leading, spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
                    AuthHeader(
                        title: "Willkommen zurück!",
                        subtitle: "Melde dich an, um dein Profil weiterzunutzen."
                    )

                    AppTextField(
                        placeholder: "E-Mail",
                        text: $email,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        autocapitalization: .never,
                        autocorrection: false
                    )

                    AppTextField(
                        placeholder: "Passwort",
                        text: $password,
                        textContentType: .password,
                        autocapitalization: .never,
                        autocorrection: false,
                        isSecure: true,
                        showsRevealToggle: true
                    )

                    helperLinks

                    if let errorMessage {
                        HStack(alignment: .top, spacing: AppMetrics.Space.s) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppColor.Status.blockedIcon)
                            Text(errorMessage)
                                .foregroundStyle(AppColor.Status.blockedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(AppTypography.footnote)
                        .accessibilityElement(children: .combine)
                    }

                    // Die Illustration läuft im Entwurf bis an beide Ränder.
                    AssetImage(name: "SplashCity", placeholderSymbol: "building.2")
                        .frame(maxWidth: .infinity, minHeight: 240)
                        .padding(.horizontal, -AppMetrics.Space.l)
                        .padding(.top, AppMetrics.Space.m)
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
        .navigationDestination(isPresented: $showResetPassword) {
            ResetPasswordView()
        }
    }

    /// Rechts «Passwort vergessen» wie im Entwurf; links daneben der
    /// Alternativweg über den Einmalcode, damit er erreichbar bleibt.
    private var helperLinks: some View {
        HStack {
            NavigationLink {
                OTPLoginView()
            } label: {
                Text("Mit Code anmelden")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColor.accentPrimary)
            }

            Spacer()

            Button("Passwort vergessen") {
                showResetPassword = true
            }
            .font(AppTypography.subheadline)
            .foregroundStyle(AppColor.accentPrimary)
        }
        .frame(minHeight: AppMetrics.Touch.minimum)
    }

    private var footer: some View {
        Button {
            Task { await handleSignIn() }
        } label: {
            if isLoading {
                ProgressView()
                    .tint(AppColor.onAccent)
            } else {
                Text("Anmelden")
            }
        }
        .buttonStyle(.appPrimary)
        .disabled(!isFormValid || isLoading)
        .padding(.horizontal, AppMetrics.Space.l)
        .padding(.top, AppMetrics.Space.m)
        .padding(.bottom, AppMetrics.Space.s)
        .background(AppColor.backgroundPrimary)
    }

    private func handleSignIn() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authService.signIn(email: email, password: password)
        } catch {
            errorMessage = ErrorText.message(for: error, context: "Anmeldung fehlgeschlagen")
        }
    }
}

#Preview {
    NavigationStack {
        SignInView()
            .environmentObject(AuthService.shared)
    }
}