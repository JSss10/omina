// CircleImageCluster.swift
// Omina
//
// Bildergruppe auf Kreisen, wie sie im Entwurf mittig auf dem Willkommens-
// Screen steht: feine Ringe im Hintergrund, darauf ein grosser Kreis in der
// Mitte und mehrere kleinere ringsherum. Jeder Kreis zeigt ein Bild aus dem
// Asset-Katalog; fehlt es noch, steht ein getönter Kreis mit SF-Symbol an
// seiner Stelle (siehe AssetMedia.swift). So bleibt die Anordnung sichtbar,
// bevor die Illustrationen vorliegen, und zeigt sie ohne Codeänderung, sobald
// die Dateien im Katalog liegen.
//
// Alle Angaben sind Anteile der Kantenlänge, damit die Gruppe als Ganzes
// skaliert, ohne dass die Kreise auseinanderfallen.

import SwiftUI

struct CircleImageCluster: View {

    /// Ein Kreis der Gruppe.
    struct Item {
        /// Name im Asset-Katalog.
        let imageName: String
        /// SF-Symbol, solange das Bild fehlt.
        let symbol: String
        /// Durchmesser als Anteil der Kantenlänge (0 … 1).
        let diameter: CGFloat
        /// Mittelpunkt als Anteil der Kantenlänge, gemessen ab der Mitte.
        let offset: CGSize
        /// Kräftigere Fläche – im Entwurf sind einzelne Kreise dunkler
        /// abgesetzt, damit die Gruppe nicht flach wirkt.
        var isAccented: Bool = false
    }

    let items: [Item]
    /// Durchmesser der feinen Hintergrundringe, als Anteil der Kantenlänge.
    var ringDiameters: [CGFloat] = []
    /// Kantenlänge der quadratischen Fläche, auf die sich alle Anteile beziehen.
    var size: CGFloat

    var body: some View {
        ZStack {
            ForEach(Array(ringDiameters.enumerated()), id: \.offset) { _, diameter in
                Circle()
                    .strokeBorder(AppColor.Violet.v300.opacity(0.45), lineWidth: 1)
                    .frame(width: size * diameter, height: size * diameter)
            }

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                circle(item)
                    .frame(width: size * item.diameter, height: size * item.diameter)
                    .offset(x: size * item.offset.width, y: size * item.offset.height)
            }
        }
        .frame(width: size, height: size)
        // Rein dekorativ: Die Aussage des Screens steht im Titel darüber.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func circle(_ item: Item) -> some View {
        let fill = item.isAccented ? AppColor.accentMuted : AppColor.surfaceTinted

        ZStack {
            Circle().fill(fill)

            if UIImage(named: item.imageName) != nil {
                Image(item.imageName)
                    .resizable()
                    .scaledToFill()
            } else {
                // Platzhalter: Symbol in der Leitfarbe, mit Luft zum Rand.
                GeometryReader { proxy in
                    Image(systemName: item.symbol)
                        .font(.system(size: proxy.size.width * 0.36, weight: .regular))
                        .foregroundStyle(AppColor.accentPrimary)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .clipShape(Circle())
    }
}

// MARK: - Anordnung des Willkommens-Screens

extension CircleImageCluster {

    /// Die Gruppe aus dem Entwurf: drei feine Ringe, ein grosser Kreis in der
    /// Mitte und neun kleinere darum herum – teils überlappend, teils
    /// abgesetzt. Die Bildnamen sind die Assets, die aus der Gestaltung
    /// kommen; fehlt eines, tritt sein Platzhalter-Symbol an seine Stelle.
    ///
    /// Die Kreise nutzen die Ringe weit aus: Die Motive sind Fotos von
    /// Bordsteinen, Rampen und Wegen, und die waren in der ersten Fassung so
    /// klein, dass nichts davon zu erkennen war. Der äusserste Kreis reicht
    /// bis knapp an den äusseren Ring – mehr Platz gibt die Fläche nicht her.
    ///
    /// Drei Bedingungen halten die Anordnung zusammen; wer einen Kreis
    /// verschiebt, prüft sie am besten nach:
    ///
    /// * Der grosse Kreis steht auf `.zero` – also genau auf der Mitte der
    ///   Ringe und damit der ganzen Fläche.
    /// * Die kleineren halten mindestens 0,075 Abstand zu seinem Rand
    ///   (rund 27 pt bei einer Kantenlänge von 354 pt), damit er frei steht
    ///   und nicht von den Nachbarn bedrängt wird.
    /// * Ihre gemeinsame Hülle misst ±0,443 waagrecht und ±0,430 senkrecht,
    ///   liegt also symmetrisch um dieselbe Mitte. Nur so steht die Gruppe
    ///   aus Ringen und Bildern als Ganzes mittig, statt zu kippen.
    ///
    /// Die Kreise haben eigene `Welcome…`-Assets und teilen sich bewusst
    /// keine Dateien mit Splash, Intro oder Onboarding: Dort stehen dieselben
    /// Motive 130 bis 400 pt breit, hier messen sie 32 bis 96 pt. Ein Bild,
    /// das beides bedienen müsste, wäre an einem der beiden Enden falsch.
    ///
    /// Der grosse Kreis steht bewusst zuletzt in der Liste: Im Stapel liegt er
    /// damit vorn, die kleineren schieben sich dahinter.
    static func welcome(size: CGFloat) -> CircleImageCluster {
        CircleImageCluster(
            items: [
                Item(
                    imageName: "WelcomeImage1",
                    symbol: "mappin.and.ellipse",
                    diameter: 0.28,
                    offset: CGSize(width: -0.25, height: -0.27)
                ),
                Item(
                    imageName: "WelcomeImage2",
                    symbol: "figure.walk",
                    diameter: 0.17,
                    offset: CGSize(width: -0.085, height: -0.303),
                    isAccented: true
                ),
                Item(
                    imageName: "WelcomeImage3",
                    symbol: "building.2.fill",
                    diameter: 0.20,
                    offset: CGSize(width: 0.343, height: -0.33)
                ),
                Item(
                    imageName: "WelcomeImage4",
                    symbol: "exclamationmark.triangle.fill",
                    diameter: 0.13,
                    offset: CGSize(width: 0.166, height: -0.244)
                ),
                Item(
                    imageName: "WelcomeImage5",
                    symbol: "eye.trianglebadge.exclamationmark",
                    diameter: 0.13,
                    offset: CGSize(width: -0.378, height: -0.02)
                ),
                Item(
                    imageName: "WelcomeImage6",
                    symbol: "figure.walk.arrival",
                    diameter: 0.15,
                    offset: CGSize(width: 0.30, height: 0.10)
                ),
                Item(
                    imageName: "WelcomeImage7",
                    symbol: "person.fill",
                    diameter: 0.26,
                    offset: CGSize(width: -0.19, height: 0.30)
                ),
                Item(
                    imageName: "WelcomeImage8",
                    symbol: "figure.and.child.holdinghands",
                    diameter: 0.155,
                    offset: CGSize(width: -0.36, height: 0.35),
                    isAccented: true
                ),
                Item(
                    imageName: "WelcomeImage9",
                    symbol: "figure.walk.motion",
                    diameter: 0.20,
                    offset: CGSize(width: 0.18, height: 0.29)
                ),
                Item(
                    imageName: "WelcomeImage10",
                    symbol: "figure.roll",
                    diameter: 0.30,
                    offset: .zero,
                    isAccented: true
                )
            ],
            ringDiameters: [0.98, 0.72, 0.46],
            size: size
        )
    }
}

#Preview {
    CircleImageCluster.welcome(size: 354)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.backgroundPrimary)
}