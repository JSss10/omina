// WelcomeView.swift
// Omina
//
// Einstieg vor der Anmeldung. Aufbau nach Entwurf: Akzentleiste, Titel mit
// Einleitung, darunter die Bildergruppe auf Kreisen und am unteren Rand die
// beiden Wege ins Konto – «Anmelden» als Hauptaktion, «Registrieren» getönt
// darunter.
//
// Die Illustrationen der Kreise folgen noch; bis dahin trägt jeder Kreis sein
// Platzhalter-Symbol (siehe CircleImageCluster.swift).

import SwiftUI

struct WelcomeView: View {
    /// Kantenlänge der Bildergruppe. Sie wächst mit der Schriftgrösse mit,
    /// aber nur bis zur Bildschirmbreite – die Gruppe ist dekorativ und soll
    /// bei grossen Textstufen nicht seitlich aus dem Screen laufen.
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 300

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

                        CircleImageCluster.welcome(size: min(heroSize, 320))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppMetrics.Space.m)
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