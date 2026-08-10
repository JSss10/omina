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
    /// kommen; bis dahin tragen die Kreise ihre Platzhalter-Symbole.
    ///
    /// Der grosse Kreis steht bewusst zuletzt in der Liste: Im Stapel liegt er
    /// damit vorn, die kleineren schieben sich dahinter.
    static func welcome(size: CGFloat) -> CircleImageCluster {
        CircleImageCluster(
            items: [
                Item(
                    imageName: "IntroPlaces",
                    symbol: "mappin.and.ellipse",
                    diameter: 0.22,
                    offset: CGSize(width: -0.25, height: -0.28)
                ),
                Item(
                    imageName: "MobilityRollator",
                    symbol: "figure.walk",
                    diameter: 0.13,
                    offset: CGSize(width: -0.12, height: -0.30),
                    isAccented: true
                ),
                Item(
                    imageName: "SplashCity",
                    symbol: "building.2.fill",
                    diameter: 0.155,
                    offset: CGSize(width: 0.33, height: -0.37)
                ),
                Item(
                    imageName: "IntroBarriers",
                    symbol: "exclamationmark.triangle.fill",
                    diameter: 0.10,
                    offset: CGSize(width: 0.13, height: -0.19)
                ),
                Item(
                    imageName: "MobilityVisualImpairment",
                    symbol: "eye.trianglebadge.exclamationmark",
                    diameter: 0.10,
                    offset: CGSize(width: -0.42, height: -0.03)
                ),
                Item(
                    imageName: "MobilityElderly",
                    symbol: "figure.walk.arrival",
                    diameter: 0.115,
                    offset: CGSize(width: 0.30, height: 0.10)
                ),
                Item(
                    imageName: "IntroProfile",
                    symbol: "person.fill",
                    diameter: 0.20,
                    offset: CGSize(width: -0.21, height: 0.28)
                ),
                Item(
                    imageName: "MobilityStroller",
                    symbol: "figure.and.child.holdinghands",
                    diameter: 0.12,
                    offset: CGSize(width: -0.33, height: 0.34),
                    isAccented: true
                ),
                Item(
                    imageName: "MobilityWalkingDisability",
                    symbol: "figure.walk.motion",
                    diameter: 0.155,
                    offset: CGSize(width: 0.17, height: 0.30)
                ),
                Item(
                    imageName: "WelcomeHero",
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
    CircleImageCluster.welcome(size: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.backgroundPrimary)
}