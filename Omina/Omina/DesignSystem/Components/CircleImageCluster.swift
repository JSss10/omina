// CircleImageCluster.swift
// Omina
//
// Bildergruppe auf Kreisen, wie sie im Entwurf mittig auf dem Willkommens-
// Screen steht: ein grosser Kreis in der Mitte, kleinere ringsherum. Jeder
// Kreis zeigt ein Bild aus dem Asset-Katalog; fehlt es noch, steht ein
// getönter Kreis mit SF-Symbol an seiner Stelle (siehe AssetMedia.swift).
// So bleibt die Anordnung sichtbar, bevor die Illustrationen vorliegen, und
// zeigt sie ohne Codeänderung, sobald die Dateien im Katalog liegen.
//
// Alle Angaben sind Anteile der Kantenlänge, damit die Gruppe mit der
// Schriftgrösse mitwächst, ohne dass die Kreise auseinanderfallen.

import SwiftUI

struct CircleImageCluster: View {

    /// Ein Kreis der Gruppe.
    struct Item: Identifiable {
        /// Name im Asset-Katalog.
        let imageName: String
        /// SF-Symbol, solange das Bild fehlt.
        let symbol: String
        /// Durchmesser als Anteil der Kantenlänge (0 … 1).
        let diameter: CGFloat
        /// Mittelpunkt als Anteil der Kantenlänge, gemessen ab der Mitte.
        let offset: CGSize
        /// Fläche hinter dem Bild bzw. hinter dem Platzhalter-Symbol.
        var isAccented: Bool = false

        var id: String { imageName }
    }

    let items: [Item]
    /// Kantenlänge der quadratischen Fläche, auf die sich alle Anteile beziehen.
    var size: CGFloat

    var body: some View {
        ZStack {
            ForEach(items) { item in
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
                        .font(.system(size: proxy.size.width * 0.38, weight: .regular))
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

    /// Die Gruppe aus dem Entwurf: grosser Kreis in der Mitte, vier kleinere
    /// darum herum. Die Bildnamen sind die Assets, die aus der Gestaltung
    /// kommen – bis dahin tragen die Kreise die Platzhalter-Symbole.
    static func welcome(size: CGFloat) -> CircleImageCluster {
        CircleImageCluster(
            items: [
                Item(
                    imageName: "IntroPlaces",
                    symbol: "mappin.and.ellipse",
                    diameter: 0.30,
                    offset: CGSize(width: -0.30, height: -0.26)
                ),
                Item(
                    imageName: "MobilityRollator",
                    symbol: "figure.walk.motion",
                    diameter: 0.26,
                    offset: CGSize(width: 0.30, height: -0.30),
                    isAccented: true
                ),
                Item(
                    imageName: "IntroBarriers",
                    symbol: "exclamationmark.triangle.fill",
                    diameter: 0.24,
                    offset: CGSize(width: -0.32, height: 0.24),
                    isAccented: true
                ),
                Item(
                    imageName: "SplashCity",
                    symbol: "building.2.fill",
                    diameter: 0.30,
                    offset: CGSize(width: 0.28, height: 0.26)
                ),
                // Der grosse Kreis liegt zuletzt im Stapel und damit vorn.
                Item(
                    imageName: "WelcomeHero",
                    symbol: "figure.roll",
                    diameter: 0.44,
                    offset: .zero,
                    isAccented: true
                )
            ],
            size: size
        )
    }
}

#Preview {
    CircleImageCluster.welcome(size: 280)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.backgroundPrimary)
}