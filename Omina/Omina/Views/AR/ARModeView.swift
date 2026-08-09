// ARModeView.swift
// Omina
//
// Vollbild-AR-Ansicht.
// Barrieren-Modus: sauberes Kamerabild, Barrieren melden sich NUR über das
// Warn-Banner (keine 3D-Objekte). POI-Modus: die POIs der Altstadt erscheinen
// als projizierte Karten im Kamerabild; das Such-Icon oben öffnet dieselbe
// Suche wie die Karte (SearchSheet) – Freitext, Kategorien, gespeicherte und
// letzte Orte. Eine gewählte Kategorie zeigt die nächstgelegenen Orte.
// Beim Start läuft ein Coaching-Overlay (Lokalisierung); nach Timeout oder
// Session-Fehler erscheint der Fehler-State mit Rückweg zur Karte.

import SwiftUI
import CoreLocation
import AVFoundation

struct ARModeView: View {
    let profile: UserProfile
    @ObservedObject var viewModel: MapViewModel
    let originCoordinate: CLLocationCoordinate2D?
    let onClose: () -> Void

    @StateObject private var arService = ARSessionService()
    @StateObject private var warningService = ProximityWarningService()
    @StateObject private var locationService = LocationService.shared
    @StateObject private var notificationStore = NotificationSettingsStore.shared
    @StateObject private var barrierNotifications = BarrierNotificationService.shared
    @StateObject private var projector = ARPOIProjector()

    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var localizationTimedOut = false
    @State private var selectedBarrier: Barrier?
    @State private var selectedPOI: POI?
    /// Suche – dasselbe Sheet wie in der Kartenansicht.
    @State private var showingSearch = false

    var body: some View {
        Group {
            switch cameraStatus {
            case .notDetermined:
                // Kein eigener Erklärungs-Screen mehr: direkt Apples System-
                // Prompt anfragen. Bis zur Antwort ein neutraler Warte-State.
                cameraRequestPlaceholder
            case .denied, .restricted:
                // Verweigert – Apples Prompt erscheint nicht erneut, daher der
                // Zustands-Screen mit Weg in die Einstellungen.
                AppStateScreen.cameraAccessDenied(onBack: onClose)
            case .authorized:
                cameraContent
            @unknown default:
                cameraContent
            }
        }
        // Gescheiterter Routenstart (Suche/POI-Karte im AR-Bild): derselbe
        // Zustands-Screen wie auf der Karte, statt eines stillen Fehlschlags.
        .overlay {
            if let failure = viewModel.routeFailure {
                AppStateScreen.routeUnavailable(
                    reason: failure.reason,
                    onRetry: { Task { await viewModel.retryFailedRoute() } },
                    onBack: {
                        viewModel.clearRouteFailure()
                        onClose()
                    }
                )
            }
        }
        .trackScreen("ar_mode")
        .task {
            try? await Task.sleep(for: .seconds(20))
            if case .starting = arService.sessionState {
                localizationTimedOut = true
            }
        }
    }

    /// Neutraler Warte-State, während Apples Kamera-Prompt beantwortet wird.
    private var cameraRequestPlaceholder: some View {
        AppStateScreen.cameraPreparing()
            .overlay(alignment: .topLeading) { dismissButton }
            .task {
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    Task { @MainActor in
                        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    }
                }
            }
    }

    @ViewBuilder
    private var cameraContent: some View {
        Group {
            if originCoordinate == nil {
                AppStateScreen.locationSignalWeak(onBack: onClose)
            } else if case .failed(let message) = arService.sessionState {
                AppStateScreen.arUnavailable(reason: message, onBack: onClose)
            } else if localizationTimedOut {
                AppStateScreen.arUnavailable(
                    reason: "Die Umgebung liess sich nicht lokalisieren. Versuche es an einem anderen Ort noch einmal.",
                    onBack: onClose
                )
            } else {
                arContent
            }
        }
    }

    private var dismissButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.title3.weight(.semibold))
                .padding(12)
                .background(.thinMaterial, in: Circle())
        }
        .padding()
        .accessibilityLabel("Zurück zur Karte")
    }

    // MARK: - AR Content

    private var arContent: some View {
        ZStack(alignment: .top) {
            ARViewContainer(
                service: arService,
                origin: originCoordinate,
                pois: viewModel.displayedPOIs,
                route: viewModel.activeRoute,
                deviceHeight: profile.arDeviceHeightM,
                projector: projector
            )
            .ignoresSafeArea()

            // Projizierte POI-Karten
            poiCards

            // Bei aktiver Navigation ersetzt das Routen-Panel (Karte + Ziel-
            // Infos + Stop) die Standard-Overlays unten. Ein Tipp auf den
            // Kartenstreifen wechselt zurück zur Karte (Navigation läuft weiter).
            if let route = viewModel.activeRoute {
                VStack(spacing: 10) {
                    Spacer()

                    ARRoutePanel(
                        route: route,
                        progress: viewModel.routeProgress,
                        maneuver: viewModel.nextManeuver,
                        alongAnchorM: viewModel.routeAnchorAlongM,
                        onStop: { viewModel.stopNavigation() },
                        onMapTap: onClose
                    )
                    .padding(.bottom, 12)
                }
            } else {
                AROverlayView(
                    userCoordinate: originCoordinate,
                    onClose: onClose
                )
            }

            VStack(spacing: 10) {
                searchRow

                // Hinweis, wenn man von der Route abkommt – mit Status der
                // automatischen Neuberechnung (die AR-Route passt sich an).
                if viewModel.isOffRoute {
                    HStack(spacing: 8) {
                        if viewModel.isRerouting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        Text(viewModel.isRerouting
                            ? "Route wird angepasst…"
                            : "Du bist von der Route abgekommen")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity)
                }

                // Fallback-Banner nur ohne Mitteilungs-Berechtigung; sonst
                // kommt die Warnung als System-Mitteilung (UserNotifications).
                if notificationStore.settings.warningsEnabled,
                   !barrierNotifications.isAuthorized,
                   let warning = warningService.activeWarning {
                    WarningBannerView(warning: warning) {
                        warningService.dismissCurrent()
                    }
                    .onTapGesture { selectedBarrier = warning.barrier }
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 8)

            // Persistenter Kompass (Blickrichtung des Geräts) oben rechts.
            CompassView(heading: locationService.heading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, 16)
                .padding(.top, 8)

            // Coaching-Overlay, solange die Session startet
            if case .starting = arService.sessionState {
                coachingOverlay
            }
        }
        .onAppear { locationService.startUpdatingHeading() }
        .animation(.spring(duration: 0.35), value: warningService.activeWarning?.barrier.id)
        .animation(.spring(duration: 0.35), value: viewModel.activeRoute?.id)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isOffRoute)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isRerouting)
        .onReceive(locationService.$currentLocation) { _ in
            evaluateProximity()
        }
        .onChange(of: viewModel.filteredBarriers.map(\.id)) { _, _ in
            evaluateProximity()
        }
        .onReceive(barrierNotifications.$tappedBarrierId) { barrierId in
            guard let barrierId,
                  let barrier = viewModel.filteredBarriers.first(where: { $0.id == barrierId })
            else { return }
            barrierNotifications.tappedBarrierId = nil
            selectedBarrier = barrier
        }
        .sheet(item: $selectedBarrier) { barrier in
            BarrierDetailSheet(barrier: barrier, profile: profile)
        }
        // Gleiche Suche wie auf der Karte. Ein Treffer öffnet direkt das
        // POI-Detail (im AR-Bild gibt es keinen Kartenausschnitt, auf den man
        // zentrieren könnte) – von dort führen "Route in AR starten" und
        // "Route anzeigen" weiter.
        .sheet(isPresented: $showingSearch) {
            SearchSheet(viewModel: viewModel) { poi in
                selectedPOI = poi
            }
            .trackScreen("ar_search")
        }
        .sheet(item: $selectedPOI) { poi in
            POIDetailSheet(
                poi: poi,
                profile: profile,
                onStartARRoute: { poi in
                    Task { await viewModel.startNavigation(to: poi, profile: profile) }
                },
                // "Route anzeigen" berechnet die Route in-App und wechselt
                // zurück zur Kartenansicht (statt Apple Karten zu öffnen);
                // die Karte zeigt die geteilte activeRoute samt Panel.
                onShowRoute: { poi in
                    Task {
                        if await viewModel.startNavigation(to: poi, profile: profile) {
                            onClose()
                        }
                    }
                }
            )
        }
    }

    // MARK: - POI-Modus

    /// Such-Icon (öffnet dasselbe SearchSheet wie die Kartenansicht) plus –
    /// falls eine Kategorie gewählt ist – ein Chip mit dieser Kategorie, der
    /// sie per Tap wieder aufhebt. Über der Kamera bewusst mit Material-
    /// Hintergrund statt der weissen Kreise der Karte, damit die Bedienelemente
    /// auf jedem Kamerabild lesbar bleiben.
    private var searchRow: some View {
        HStack(spacing: 8) {
            Button {
                showingSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            }
            .accessibilityLabel("Orte suchen")

            if let category = viewModel.activeCategory {
                Button {
                    viewModel.setCategory(nil)
                } label: {
                    HStack(spacing: 6) {
                        Text(category)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: Capsule())
                }
                .accessibilityLabel("Kategorie \(category) aufheben")
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var poiCards: some View {
        GeometryReader { _ in
            ForEach(projector.projected) { item in
                POIARMarker(poi: item.poi)
                    .position(item.point)
                    .onTapGesture { selectedPOI = item.poi }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Coaching

    private var coachingOverlay: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)

                Text("Richte die Kamera auf Gebäude")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Bewege dein iPhone langsam")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))

                Text("Lokalisierung…".uppercased())
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 8)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Helpers

    private func evaluateProximity() {
        warningService.evaluate(
            userLocation: locationService.currentLocation,
            barriers: viewModel.filteredBarriers,
            profile: profile
        )
    }
}

// MARK: - POI-Marker im AR-Raum

/// Kreis-Badge mit Kategorie-Icon, das über einem gepunkteten Strich am
/// projizierten POI-Punkt "schwebt" (Ankerpunkt unten). Der innere Kreis
/// trägt Violett 700 (wie der Karten-Marker), das kleine Status-Icon oben
/// rechts zeigt die Zugänglichkeit als Symbol (Häkchen/Warndreieck/Kreuz).
struct POIARMarker: View {
    let poi: POI

    private static let badgeSize: CGFloat = 52
    private static let stemHeight: CGFloat = 44
    private static let anchorSize: CGFloat = 7

    var body: some View {
        VStack(spacing: 2) {
            badge

            DashedVerticalLine()
                .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 6]))
                .foregroundStyle(.white)
                .frame(width: 2, height: Self.stemHeight)
                .shadow(color: .black.opacity(0.35), radius: 1)

            Circle()
                .fill(.white)
                .frame(width: Self.anchorSize, height: Self.anchorSize)
                .shadow(color: .black.opacity(0.35), radius: 1)
        }
        // .position() zentriert die View am projizierten Punkt; nach oben
        // verschieben, damit der Ankerpunkt (unten) auf dem Punkt liegt.
        .offset(y: -(Self.badgeSize + Self.stemHeight) / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(poi.name), \(poi.accessStatus.shortLabel), \(DistanceFormatter.string(fromMeters: poi.distanceM))")
        .accessibilityAddTraits(.isButton)
    }

    private var badge: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: Self.badgeSize, height: Self.badgeSize)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                Circle()
                    .fill(AppColor.Violet.v700)
                    .frame(width: Self.badgeSize - 12, height: Self.badgeSize - 12)
                Image(systemName: poi.categorySymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }

            POIStatusIcon(status: poi.accessStatus, diameter: 19)
                .offset(x: 2, y: -2)
        }
    }
}

/// Vertikale Linie für den gepunkteten Marker-Strich.
struct DashedVerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}