// WelcomeView.swift
// Omina
//
// Einstieg vor der Anmeldung. Aufbau nach Entwurf: Akzentleiste, Titel mit
// Einleitung, darunter die Illustration und am unteren Rand die beiden Wege
// ins Konto – «Anmelden» als Hauptaktion, «Registrieren» getönt darunter.
//
// Die Illustration (Asset "WelcomeHero") folgt noch; bis dahin steht der
// Platzhalter an ihrer Stelle (siehe AssetMedia.swift).

import SwiftUI

struct WelcomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BrandAccentBar()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        AuthHeader(
                            title: "Willkommen",
                            subtitle: "Melde dich an oder erstelle ein Konto."
                        )

                        AssetImage(name: "WelcomeHero", placeholderSymbol: "circle.hexagongrid")
                            .frame(maxWidth: .infinity, minHeight: 260)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, AppMetrics.Space.l)
                    .padding(.bottom, AppMetrics.Space.m)
                }
                .scrollBounceBehavior(.basedOnSize)

                footer
            }
            .background(AppColor.backgroundPrimary.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var footer: some View {
        VStack(spacing: AppMetrics.Space.s + AppMetrics.Space.xs) {
            // Feldtest Altstadt Zürich: Testpersonen wählen ein vorgefertigtes
            // Profil, statt sich zu registrieren.
            if AppConfig.fieldTestModeEnabled {
                NavigationLink {
                    TestProfileSelectionView()
                } label: {
                    Text("Feldtest starten")
                }
                .buttonStyle(.appSecondary(fullWidth: true))
            }

            NavigationLink {
                SignInView()
            } label: {
                Text("Anmelden")
            }
            .buttonStyle(.appPrimary(fullWidth: true))

            NavigationLink {
                IntroCarouselView()
            } label: {
                Text("Registrieren")
            }
            .buttonStyle(.appQuiet(fullWidth: true))
        }
        .padding(.horizontal, AppMetrics.Space.l)
        .padding(.top, AppMetrics.Space.m)
        .padding(.bottom, AppMetrics.Space.s)
        .background(AppColor.backgroundPrimary)
    }
}

#Preview {
    WelcomeView()
        .environmentObject(AuthService.shared)
}