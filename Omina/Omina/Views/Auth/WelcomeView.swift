// WelcomeView.swift
// Omina
//
// Einstieg vor der Anmeldung. Aufbau nach Entwurf: Akzentleiste, Titel mit
// Einleitung, darunter die Bildergruppe auf Kreisen und am unteren Rand die
// beiden Wege ins Konto – «Anmelden» als Hauptaktion, «Registrieren» getönt
// darunter.
//
// Die Bildergruppe (Assets "Welcome…") steht als Ganzes mittig in der Fläche
// zwischen Kopf und Fusszeile; fehlt ein Bild, trägt der Kreis sein
// Platzhalter-Symbol (siehe CircleImageCluster.swift).

import SwiftUI

struct WelcomeView: View {
    /// Obergrenze für die Kantenlänge der Bildergruppe. Sie wächst mit der
    /// Schriftgrösse mit, bleibt aber innerhalb der Textränder – die Gruppe
    /// ist dekorativ und soll nicht seitlich aus dem Screen laufen.
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 360

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BrandAccentBar()

                // Die Geometrie der freien Fläche wird gebraucht, damit die
                // Gruppe die volle Satzbreite nutzen und mittig darin stehen
                // kann, statt oben zu kleben.
                GeometryReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            AuthHeader(
                                title: "Willkommen",
                                subtitle: "Melde dich an oder erstelle ein Konto."
                            )

                            // Zwei gleich starke Abstandshalter teilen den
                            // Rest der Fläche: Die Gruppe steht damit in
                            // deren Mitte. Reicht der Platz nicht (grosse
                            // Textstufen), schrumpfen sie auf ihr Minimum
                            // und der Screen wird scrollbar.
                            Spacer(minLength: AppMetrics.Space.m)

                            CircleImageCluster.welcome(size: heroSide(in: proxy.size))
                                .frame(maxWidth: .infinity)

                            Spacer(minLength: AppMetrics.Space.m)
                        }
                        .padding(.horizontal, AppMetrics.Space.l)
                        .frame(minHeight: proxy.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }

                footer
            }
            .background(AppColor.backgroundPrimary.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Kantenlänge der Bildergruppe: die Breite des Textsatzes, höchstens
    /// aber `heroSize`.
    private func heroSide(in available: CGSize) -> CGFloat {
        max(0, min(heroSize, available.width - 2 * AppMetrics.Space.l))
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