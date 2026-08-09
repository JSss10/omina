// UserLocationMarker.swift
// Omina
//
// Standort-Marker für Karte und AR-Minikarte: der Positionspunkt plus ein
// Blickrichtungs-Kegel, der sich mit der Geräteausrichtung mitdreht – so
// sieht man jederzeit, in welche Richtung man gerade schaut (wie der
// Blickkegel am blauen Punkt in Apple Karten). Ohne bekannte Richtung wird
// nur der Punkt gezeigt.

import SwiftUI
import CoreLocation

struct UserLocationMarker: View {
    /// Blickrichtung relativ zur Oben-Richtung der Karte (Grad, im
    /// Uhrzeigersinn). Bei einer gedrehten Karte muss die Geräteausrichtung
    /// bereits um die Kartendrehung bereinigt sein. `nil` → Richtung
    /// unbekannt, es wird nur der Punkt gezeigt.
    let headingDegrees: CLLocationDirection?

    /// Öffnungswinkel des Kegels in Grad.
    private let coneSpread: Double = 70
    /// Länge des Kegels (Radius ab dem Punkt) in Punkten.
    private let coneLength: CGFloat = 30
    /// Durchmesser des Positionspunkts in Punkten.
    private let dotDiameter: CGFloat = 22

    var body: some View {
        ZStack {
            // Blickrichtungs-Kegel hinter dem Punkt; dreht mit der Richtung.
            if let headingDegrees {
                HeadingCone(spreadDegrees: coneSpread)
                    .fill(
                        RadialGradient(
                            colors: [
                                AppColor.accentPrimary.opacity(0.55),
                                AppColor.accentPrimary.opacity(0),
                            ],
                            center: .center,
                            startRadius: dotDiameter / 2,
                            endRadius: coneLength
                        )
                    )
                    .rotationEffect(.degrees(headingDegrees))
            }

            // Positionspunkt (weisser Ring, Akzent-Kern) – dreht nicht mit.
            Circle()
                .fill(.white)
                .frame(width: dotDiameter, height: dotDiameter)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            Circle()
                .fill(AppColor.accentPrimary)
                .frame(width: dotDiameter - 6, height: dotDiameter - 6)
        }
        // Quadratischer Rahmen um den Punkt: Die Kegelspitze liegt im Zentrum,
        // dadurch dreht der Kegel um den Standortpunkt.
        .frame(width: coneLength * 2, height: coneLength * 2)
        .animation(.easeOut(duration: 0.2), value: headingDegrees)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Kegel/Strahl mit Spitze im Mittelpunkt, nach oben geöffnet – als
/// Blickrichtungs-Anzeige. Rotiert um den Mittelpunkt (= Standortpunkt).
private struct HeadingCone: Shape {
    let spreadDegrees: Double

    func path(in rect: CGRect) -> Path {
        let apex = CGPoint(x: rect.midX, y: rect.midY)
        let apexX = Double(rect.midX)
        let apexY = Double(rect.midY)
        let radius = Double(min(rect.width, rect.height) / 2)
        // Bildschirm-Koordinaten (y nach unten): oben = -90°.
        let up = -Double.pi / 2
        let half = spreadDegrees * .pi / 180 / 2

        // Sektor punktweise aufbauen, unabhängig von der Bogenrichtung.
        var path = Path()
        path.move(to: apex)
        let steps = 24
        for i in 0...steps {
            let angle = (up - half) + (2 * half) * Double(i) / Double(steps)
            path.addLine(to: CGPoint(
                x: apexX + radius * cos(angle),
                y: apexY + radius * sin(angle)
            ))
        }
        path.closeSubpath()
        return path
    }
}