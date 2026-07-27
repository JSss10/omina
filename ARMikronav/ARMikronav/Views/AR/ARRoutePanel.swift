// ARRoutePanel.swift
// ARMikronav
//
// Bottom-Panel während der AR-Navigation: Kartenstreifen mit Routenverlauf
// (eng an den aktuellen Standort gezoomt und diesem folgend, gleiches
// Styling wie die Navigations-Karte), darunter die geteilte RouteInfoBar
// mit Richtungspfeil, Zielname, Restzeit/-distanz und Stop-Button. Ein Tipp
// auf den Kartenstreifen wechselt zurück zur Kartenansicht (ersetzt den
// früheren "Zur Karte"-Button).

import SwiftUI
import MapKit
import CoreLocation
import Combine

struct ARRoutePanel: View {
    let route: ActiveRoute
    let progress: RouteProgress?
    var maneuver: RouteManeuver? = nil
    /// Bisher zurückgelegte Weglänge auf der Route – hält das Einrasten des
    /// Standortpunkts auf demselben Routenast wie in der Kartenansicht.
    var alongAnchorM: CLLocationDistance? = nil
    let onStop: () -> Void
    /// Tipp auf den Kartenstreifen → zurück zur Kartenansicht.
    var onMapTap: (() -> Void)? = nil

    @StateObject private var locationService = LocationService.shared
    @State private var cameraPosition: MapCameraPosition

    init(
        route: ActiveRoute,
        progress: RouteProgress?,
        maneuver: RouteManeuver? = nil,
        alongAnchorM: CLLocationDistance? = nil,
        onStop: @escaping () -> Void,
        onMapTap: (() -> Void)? = nil
    ) {
        self.route = route
        self.progress = progress
        self.maneuver = maneuver
        self.alongAnchorM = alongAnchorM
        self.onStop = onStop
        self.onMapTap = onMapTap
        _cameraPosition = State(initialValue: .region(Self.fittedRegion(for: route)))
    }

    var body: some View {
        VStack(spacing: 0) {
            routeMap
                .frame(height: 130)

            RouteInfoBar(route: route, progress: progress, maneuver: maneuver, onStop: onStop)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 6)
        .padding(.horizontal, 12)
    }

    // MARK: - Karte

    private var routeMap: some View {
        Map(position: $cameraPosition) {
            MapPolyline(coordinates: route.coordinates)
                .stroke(
                    AppColor.accentPrimary,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                )
            // Standortpunkt mit Blickrichtungs-Kegel; die Minikarte ist
            // nordausgerichtet, daher zeigt die Kamera-Blickrichtung direkt
            // (funktioniert auch bei aufrecht gehaltenem iPhone). Der Punkt
            // rastet auf die Route ein, solange man nah genug an ihr ist, damit
            // er nicht neben der Linie springt.
            if let userLocation = locationService.currentLocation {
                Annotation("", coordinate: snappedCoordinate(for: userLocation), anchor: .center) {
                    UserLocationMarker(headingDegrees: locationService.viewingDirection)
                }
            }
            Marker(
                route.destinationName,
                systemImage: "mappin",
                coordinate: route.destinationCoordinate
            )
            .tint(AppColor.accentPrimary)
        }
        .mapDisplayPreferences()
        .allowsHitTesting(false)
        // Die Minikarte zeigt stets die ganze Route (Start bis Ziel) – der
        // Standortpunkt bewegt sich darin, der Ausschnitt bleibt aber fix, damit
        // man jederzeit den kompletten Verlauf sieht. Bei einer Neuberechnung
        // (neue Route-ID) wird der Ausschnitt auf die neue Route angepasst.
        .onChange(of: route.id) { _, _ in
            withAnimation(.easeInOut) {
                cameraPosition = .region(Self.fittedRegion(for: route))
            }
        }
        // Tap-Fläche über der (nicht interaktiven) Karte: wechselt zur Karte.
        .overlay {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onMapTap?() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zur Karte wechseln")
        .accessibilityAddTraits(.isButton)
    }

    /// Maximaler seitlicher Abstand (Meter), bis zu dem der Standortpunkt auf
    /// die Route eingerastet wird.
    private static let snapToRouteMaxOffsetM: CLLocationDistance = 12

    /// Standortkoordinate für den Marker: auf die Route eingerastet, solange
    /// man nah genug an ihr ist – sonst die Rohposition.
    private func snappedCoordinate(for location: CLLocation) -> CLLocationCoordinate2D {
        let snap = RouteService.snappedLocation(on: route, at: location, alongAnchorM: alongAnchorM)
        return snap.offsetM <= Self.snapToRouteMaxOffsetM ? snap.coordinate : location.coordinate
    }

    /// Kartenausschnitt, der die komplette Route (Start bis Ziel) mit etwas
    /// Rand umfasst – so ist der ganze Verlauf im Kartenmodul sichtbar. Der
    /// Zoom passt sich der Routenlänge an (mit sinnvoller Unter-/Obergrenze,
    /// damit sehr kurze Routen nicht übermässig herangezoomt werden).
    private static func fittedRegion(for route: ActiveRoute) -> MKCoordinateRegion {
        let coordinates = route.coordinates
        guard let first = coordinates.first else {
            // Ohne Wegpunkte wenigstens das Ziel zentrieren.
            return MKCoordinateRegion(
                center: route.destinationCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
            )
        }

        var minLat = first.latitude, maxLat = first.latitude
        var minLng = first.longitude, maxLng = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLng = min(minLng, coordinate.longitude)
            maxLng = max(maxLng, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        // 40 % Rand rundum, damit Start- und Zielmarker nicht am Kartenrand
        // kleben; Untergrenze für sehr kurze Routen.
        let latDelta = max((maxLat - minLat) * 1.4, 0.0012)
        let lngDelta = max((maxLng - minLng) * 1.4, 0.0012)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
        )
    }
}