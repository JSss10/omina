// CompassView.swift
// Omina
//
// Kompass-Overlay für Karten- und AR-Ansicht. Zeigt eine kompakte
// Kompassrose, die sich mit der Blickrichtung des Geräts dreht: Die rote
// Nordnadel zeigt immer nach geografisch Norden, unabhängig davon, wie das
// iPhone gehalten wird. Die Blickrichtung kommt vom LocationService.

import SwiftUI
import CoreLocation

struct CompassView: View {
    /// Geräteausrichtung in Grad (0 = Norden). `nil` → Kompass ist inaktiv.
    let heading: CLLocationDirection?
    /// Hintergrund des Trägerkreises. Auf der Karte ein deckendes Weiss
    /// (konsistent mit Such- und Einstellungs-Button); im AR-Modus bleibt der
    /// durchscheinende Standard erhalten.
    private let background: AnyShapeStyle

    private var diameter: CGFloat = 44

    init(
        heading: CLLocationDirection?,
        background: AnyShapeStyle = AnyShapeStyle(.thinMaterial)
    ) {
        self.heading = heading
        self.background = background
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(background)
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))

            // Kompassrose dreht entgegen der Blickrichtung, damit Norden
            // ortsfest bleibt.
            rose
                .rotationEffect(.degrees(-(heading ?? 0)))
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        .animation(.easeOut(duration: 0.2), value: heading)
        .accessibilityElement()
        .accessibilityLabel("Kompass")
        .accessibilityValue(accessibilityValue)
    }

    private var rose: some View {
        ZStack {
            // Nord-Nadel (rot) oben, Süd-Nadel (grau) unten.
            VStack(spacing: 0) {
                Triangle()
                    .fill(.red)
                    .frame(width: 9, height: 11)
                Triangle()
                    .fill(Color(.systemGray))
                    .frame(width: 9, height: 11)
                    .rotationEffect(.degrees(180))
            }

            // Himmelsrichtung „N“ am oberen Rand.
            Text("N")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.primary)
                .offset(y: -(diameter / 2) + 8)
        }
    }

    private var accessibilityValue: String {
        guard let heading else { return "Richtung unbekannt" }
        let compass = ["Norden", "Nordosten", "Osten", "Südosten",
                       "Süden", "Südwesten", "Westen", "Nordwesten"]
        let index = Int((heading / 45).rounded()) % 8
        return "Blickrichtung \(compass[max(0, index)]), \(Int(heading.rounded())) Grad"
    }
}

/// Gleichschenkliges Dreieck mit Spitze oben (für die Kompassnadel).
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}