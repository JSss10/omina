// AROverlayView.swift
// Omina
//
// SwiftUI-Overlay über der ARView ohne aktive Route: Kartenstreifen unten
// im gleichen Styling wie das Routen-Panel (ARRoutePanel), nah an den
// Standort gezoomt. Die Karte zeigt bewusst nur den Standort – keine
// Barrieren-Marker –, damit der Ausschnitt aufgeräumt bleibt. Ein Tipp auf
// die Karte wechselt zurück zur Kartenansicht (ersetzt den früheren
// "Zur Karte"-Button).

import SwiftUI
import MapKit
import CoreLocation

struct AROverlayView: View {
    let userCoordinate: CLLocationCoordinate2D?
    let onClose: () -> Void

    @StateObject private var locationService = LocationService.shared

    var body: some View {
        VStack {
            Spacer()
            miniMap
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    // MARK: - Components

    private var miniMap: some View {
        Group {
            if let userCoordinate {
                Map(initialPosition: .region(region(around: userCoordinate))) {
                    // Standortpunkt mit Blickrichtungs-Kegel; die Minikarte ist
                    // nordausgerichtet, daher zeigt die Kamera-Blickrichtung
                    // direkt (funktioniert auch bei aufrecht gehaltenem iPhone).
                    Annotation("", coordinate: userCoordinate, anchor: .center) {
                        UserLocationMarker(headingDegrees: locationService.viewingDirection)
                    }
                }
                .mapDisplayPreferences()
                .allowsHitTesting(false)
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .frame(height: 130)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 6)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture { onClose() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zur Karte wechseln")
        .accessibilityAddTraits(.isButton)
    }

    // Enger Ausschnitt (~100 m), damit die unmittelbare Umgebung und eine
    // startende Route direkt erkennbar sind.
    private func region(around coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)
        )
    }
}