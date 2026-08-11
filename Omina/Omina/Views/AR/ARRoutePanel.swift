// ARRoutePanel.swift
// Omina
//
// Bottom-Panel während der AR-Navigation, Aufbau nach Entwurf: dieselbe
// Kopfzeile, Zusammenfassung und Fortschrittsleiste wie in der Kartenansicht
// (MapRoutePanel), darunter der Kartenstreifen mit dem Routenverlauf. Ein Tipp
// auf den Streifen wechselt zurück zur Kartenansicht.
//
// Der Kartenstreifen verhält sich wie die grosse Karte im Folgen-Modus: Er
// zentriert auf den eigenen Standort und dreht sich mit der eigenen
// Ausrichtung mit (Blickrichtung nach oben). Damit stimmen Kamerabild,
// AR-Pfad und Kartenstreifen überein – vorher stand die Minikarte
// nordausgerichtet fix auf der ganzen Route, was beim Vergleich mit dem
// Kamerabild jedes Mal im Kopf umgerechnet werden musste.

import SwiftUI
import MapKit
import CoreLocation
import Combine

struct ARRoutePanel: View {
    let route: ActiveRoute
    let progress: RouteProgress?
    /// Bisher zurückgelegte Weglänge auf der Route – hält das Einrasten des
    /// Standortpunkts auf demselben Routenast wie in der Kartenansicht.
    var alongAnchorM: CLLocationDistance? = nil
    let onStop: () -> Void
    /// Tipp auf den Kartenstreifen → zurück zur Kartenansicht.
    var onMapTap: (() -> Void)? = nil
    /// Öffnet die Wegbeschreibung als Liste (Kopfzeile rechts).
    var onShowSteps: (() -> Void)? = nil

    @StateObject private var locationService = LocationService.shared
    @State private var cameraPosition: MapCameraPosition
    /// Geglättete Richtung und Drosselung der Kameraführung – derselbe
    /// Referenztyp wie in der Kartenansicht, damit die laufenden
    /// Zwischenwerte kein View-Update auslösen.
    @State private var camera = NavigationCameraState()

    init(
        route: ActiveRoute,
        progress: RouteProgress?,
        alongAnchorM: CLLocationDistance? = nil,
        onStop: @escaping () -> Void,
        onMapTap: (() -> Void)? = nil,
        onShowSteps: (() -> Void)? = nil
    ) {
        self.route = route
        self.progress = progress
        self.alongAnchorM = alongAnchorM
        self.onStop = onStop
        self.onMapTap = onMapTap
        self.onShowSteps = onShowSteps
        _cameraPosition = State(initialValue: .region(Self.fittedRegion(for: route)))
    }

    var body: some View {
        VStack(spacing: AppMetrics.Space.m) {
            RoutePanelHeader(
                hasArrived: progress?.hasArrived ?? false,
                onStop: onStop,
                onShowSteps: onShowSteps
            )

            RouteSummaryRow(route: route, progress: progress)
            RouteProgressBar(route: route, progress: progress)

            // Kartenstreifen: zeigt denselben Ausschnitt wie das Kamerabild,
            // ein Tipp darauf wechselt zur Kartenansicht.
            routeMap
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous))
        }
        .padding(.horizontal, AppMetrics.Space.l)
        .padding(.top, AppMetrics.Space.m)
        .padding(.bottom, AppMetrics.Space.m)
        // Wie in der Kartenansicht: Die Fläche läuft bis an den unteren
        // Bildschirmrand, der Inhalt bleibt über dem Home-Indikator.
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: AppMetrics.Radius.sheet + AppMetrics.Space.s,
                topTrailingRadius: AppMetrics.Radius.sheet + AppMetrics.Space.s,
                style: .continuous
            )
            .fill(AppColor.surfaceOverlay)
            .shadow(color: AppColor.textBrand.opacity(0.2), radius: 12, y: -2)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Karte

    private var routeMap: some View {
        Map(position: $cameraPosition) {
            // Wie in der Kartenansicht: nur der Weg voraus ist kräftig, das
            // bereits Zurückgelegte bleibt blass sichtbar.
            let parts = routeParts
            if parts.covered.count >= 2 {
                MapPolyline(coordinates: parts.covered)
                    .stroke(
                        AppColor.accentPrimary.opacity(0.28),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
            }
            MapPolyline(coordinates: parts.remaining)
                .stroke(
                    AppColor.accentPrimary,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                )
            // Standortpunkt mit Blickrichtungs-Kegel. Die Karte dreht sich mit,
            // deshalb wird die Geräteausrichtung um die Kartendrehung bereinigt
            // – der Kegel zeigt dadurch (bis auf die Nachführ-Verzögerung) nach
            // oben. Der Punkt rastet auf die Route ein, solange man nah genug an
            // ihr ist, damit er nicht neben der Linie springt.
            if let userLocation = locationService.currentLocation {
                Annotation("", coordinate: snappedCoordinate(for: userLocation), anchor: .center) {
                    UserLocationMarker(headingDegrees: coneHeading)
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
        // Dem Standort folgen und mitdrehen – wie die grosse Karte.
        .onReceive(locationService.$currentLocation) { _ in
            updateCamera(force: true)
        }
        // Auch beim Drehen auf der Stelle nachführen; dafür genügen
        // Standort-Updates nicht.
        .onReceive(headingUpdates) { _ in
            updateCamera()
        }
        // Neuberechnung: sofort auf den neuen Verlauf nachführen.
        .onChange(of: route.id) { _, _ in
            updateCamera(force: true)
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

    // MARK: - Kameraführung (folgt dem Standort, dreht mit)

    /// Kameraabstand des Streifens – eng genug, dass die nächsten Meter
    /// erkennbar sind, weit genug für den nächsten Abbieger.
    private static let followDistanceM: CLLocationDistance = 170
    /// Mindestabstand zwischen zwei Nachführungen (die Blickrichtung kommt
    /// mit ~20 Hz).
    private static let cameraUpdateIntervalS: TimeInterval = 0.25
    /// Ab dieser Richtungsänderung wird nachgedreht – kleinere Zappler bleiben
    /// unbeachtet, damit der schmale Streifen ruhig steht.
    private static let cameraHeadingStepDeg: Double = 3

    /// Blickrichtungs-Updates (Kompass und – aufrecht gehalten – die aus der
    /// Gerätelage bestimmte Kamerarichtung).
    private var headingUpdates: AnyPublisher<CLLocationDirection?, Never> {
        Publishers.Merge(locationService.$heading, locationService.$lookDirection)
            .eraseToAnyPublisher()
    }

    /// Blickrichtung des Kegels relativ zur gedrehten Karte.
    private var coneHeading: CLLocationDirection? {
        guard let direction = locationService.viewingDirection else { return nil }
        return direction - (camera.appliedHeadingDeg ?? 0)
    }

    /// Zentriert den Streifen auf den eigenen Standort und dreht ihn in die
    /// eigene Blickrichtung. `force` (Standort-Update, neue Route) übergeht
    /// die Drosselung.
    private func updateCamera(force: Bool = false) {
        guard let location = locationService.currentLocation else { return }

        let now = Date()
        if !force,
           let last = camera.lastUpdateAt,
           now.timeIntervalSince(last) < Self.cameraUpdateIntervalS { return }

        guard let heading = smoothedHeading(at: location) else { return }
        if !force,
           let applied = camera.appliedHeadingDeg,
           abs(ARHeadingCorrection.normalizedSignedDegrees(heading - applied))
            < Self.cameraHeadingStepDeg { return }

        camera.lastUpdateAt = now
        camera.appliedHeadingDeg = heading

        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: snappedCoordinate(for: location),
                    distance: Self.followDistanceM,
                    heading: heading,
                    pitch: 0
                )
            )
        }
    }

    /// Geglättete Drehrichtung: bevorzugt die eigene Blickrichtung,
    /// ersatzweise die Fahrtrichtung der Route.
    private func smoothedHeading(at location: CLLocation) -> CLLocationDirection? {
        let target = locationService.viewingDirection
            ?? RouteService.travelBearingDegrees(
                of: route,
                at: location,
                alongAnchorM: alongAnchorM
            )
        guard let target else { return nil }

        let smoothed = ARHeadingCorrection.smooth(
            previous: camera.smoothedHeadingDeg,
            new: target,
            factor: 0.3
        )
        camera.smoothedHeadingDeg = smoothed
        return (smoothed + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Route aufgeteilt in "schon gefahren" und "liegt noch vor mir".
    private var routeParts: (
        covered: [CLLocationCoordinate2D],
        remaining: [CLLocationCoordinate2D]
    ) {
        guard let location = locationService.currentLocation else {
            return ([], route.coordinates)
        }
        return RouteService.split(route, at: location.coordinate, alongAnchorM: alongAnchorM)
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

    /// Startausschnitt, bis der erste Standort-Fix da ist: die komplette Route
    /// (Start bis Ziel) mit etwas Rand. Danach übernimmt die mitdrehende
    /// Kameraführung (`updateCamera`).
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