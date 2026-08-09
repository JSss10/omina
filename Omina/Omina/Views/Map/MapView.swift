// MapView.swift
// Omina
//
// Kartenansicht (iOS 17 Map API). Startregion: aktueller Standort bzw. als
// Fallback die Altstadt Zürich; POIs und Barrieren werden für die ganze
// Zürcher Altstadt geladen. Zeigt Userposition, profilrelevante Barrieren,
// POI-Marker mit Zugänglichkeits-Status, Suchleiste (inkl. Kategorie-Filter)
// und ein Annäherungs-Banner. Bei aktiver Route erscheinen nur die Barrieren
// direkt auf der Route. MapViewModel kommt vom HomeView, damit Filter-
// und Barrieren-State mit dem AR-Modus geteilt werden.
//
// Kameraführung während der Navigation (Feldtest-Rückmeldung):
// – Beim Start einer Route zeigt die Karte die GANZE Strecke – vom eigenen
//   Standort bis zum Ziel – im freien Bereich zwischen den Bedienelementen
//   oben und dem Routen-Panel unten. Der Button rechts oben wechselt auf
//   "dem Standort folgen" und zurück.
// – Die Karte dreht sich in beiden Modi mit der EIGENEN Ausrichtung mit
//   (Blickrichtung nach oben), statt starr der Routenrichtung zu folgen.
// – Danach wird die Zoomstufe NIE automatisch verändert: Was der User mit
//   den Fingern einstellt, bleibt stehen; ein eigener Kartengriff pausiert
//   die automatische Führung kurz, damit sie nicht dagegenhält. Auch eine
//   automatische Neuberechnung lässt den Zoom in Ruhe.

import SwiftUI
import Combine
import MapKit
import CoreLocation

struct MapView: View {
    let profile: UserProfile
    @ObservedObject var viewModel: MapViewModel
    /// Startet die AR-Navigation zum POI (HomeView wechselt in den AR-Modus).
    var onStartARRoute: ((POI) -> Void)? = nil

    @StateObject private var locationService = LocationService.shared
    @StateObject private var connectivity = ConnectivityMonitor.shared
    @StateObject private var proximityService = ProximityWarningService()
    @StateObject private var barrierNotifications = BarrierNotificationService.shared
    @StateObject private var mapPreferences = MapPreferences.shared

    @State private var cameraPosition: MapCameraPosition = .region(MapView.defaultRegion)
    @State private var selectedBarrier: Barrier?
    @State private var selectedPOI: POI?
    /// Auf der Karte hervorgehobener, zuletzt gewählter POI (z. B. aus der
    /// Suche) – bleibt als Marker sichtbar, auch wenn er nicht unter den
    /// angezeigten POIs in der Nähe ist.
    @State private var focusedPOI: POI?
    @State private var showingSearch = false
    /// Karteneinstellungen (Kartenmodus, Darstellung) – über den Ebenen-Button
    /// links oben. Sichtbarkeit und Barrieretypen liegen im Filter-Sheet
    /// (Icon in der Suchleiste bzw. über den Empty-State).
    @State private var showingMapSettings = false
    /// Filter-Sheet (Sichtbarkeit von Orten/Barrieren + Barrieretypen), auch
    /// direkt aus dem Empty-State heraus erreichbar.
    @State private var showingFilter = false
    /// Routenplanung (Bedienstapel rechts auf der Karte).
    @State private var showingRoutes = false
    /// Listenansicht der Barrieren entlang der aktiven Route.
    @State private var showingRouteBarriers = false
    /// Turn-by-turn-Listenansicht der aktiven Route.
    @State private var showingRouteSteps = false
    /// In der Barrieren-Liste angetippte Barriere: wird nach dem Schliessen
    /// der Liste als Detail-Sheet geöffnet (zwei Sheets nicht gleichzeitig).
    @State private var pendingListBarrier: Barrier?
    /// Zustands-Screen "Standort nicht freigegeben" weggetippt: Die Karte ist
    /// auch ohne Standort nützlich (Altstadt-Barrieren und -Orte), deshalb
    /// bleibt sie über "Karte trotzdem ansehen" erreichbar.
    @State private var locationStateDismissed = false
    /// Einmaliges Zentrieren auf den Standort beim ersten GPS-Fix. Danach
    /// bleibt der vom User gewählte Kartenausschnitt (Zoom/Position) stehen,
    /// bis eine Aktion (Suche, Route, Standort-Button) die Kamera bewegt.
    @State private var hasCenteredOnUser = false
    /// Aktuelle Drehung der Karte (Grad, im Uhrzeigersinn) – nötig, um den
    /// Blickrichtungs-Kegel bei gedrehter Karte richtig auszurichten.
    @State private var mapHeading: CLLocationDirection = 0
    /// Kameramodus während einer aktiven Route: Übersicht über die ganze
    /// Strecke (Startzustand) oder Folgen des eigenen Standorts.
    @State private var routeCameraMode: RouteCameraMode = .overview
    /// Laufende Zwischenwerte der Kameraführung (siehe Klasse unten).
    @State private var navCamera = NavigationCameraState()

    /// Kameramodus während der Navigation.
    enum RouteCameraMode {
        /// Ganze Route im Bild, Kamera bleibt stehen.
        case overview
        /// Kamera folgt dem Standort und dreht sich mit der eigenen Ausrichtung.
        case following
    }

    // Enger Zoom (~150 m Bildausschnitt), damit nur Barrieren in unmittelbarer
    // Nähe des aktuellen Standorts sichtbar sind.
    static let closeUpSpan = MKCoordinateSpan(latitudeDelta: 0.0015, longitudeDelta: 0.0015)

    static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(
            latitude: (AppConfig.testAreaMinLat + AppConfig.testAreaMaxLat) / 2,
            longitude: (AppConfig.testAreaMinLng + AppConfig.testAreaMaxLng) / 2
        ),
        span: closeUpSpan
    )

    var body: some View {
        mapContainer {
            // Standortpunkt mit Blickrichtungs-Kegel. Die Geräteausrichtung
            // wird um die aktuelle Kartendrehung bereinigt, damit der Kegel
            // auch bei gedrehter Karte (Navigation) korrekt dorthin zeigt,
            // wohin man schaut.
            if let userLocation = locationService.currentLocation {
                Annotation("", coordinate: snappedUserCoordinate(for: userLocation), anchor: .center) {
                    UserLocationMarker(headingDegrees: userConeHeading)
                }
            }

            // Aktive Navigations-Route (geteilt mit dem AR-Modus). Der bereits
            // zurückgelegte Teil wird nur blass gezeichnet: Sonst sieht die
            // gefahrene Schlaufe hinter einem aus wie ein Umweg, der noch
            // bevorsteht (Feldtest-Rückmeldung).
            if let route = viewModel.activeRoute {
                let parts = routeParts(of: route)
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
                // Ziel-Pin nur als Fallback ohne Ziel-POI – sonst markiert der
                // POI-Marker (displayedPOIs) das Ziel.
                if viewModel.navigationTarget == nil {
                    Marker(
                        route.destinationName,
                        systemImage: "mappin",
                        coordinate: route.destinationCoordinate
                    )
                    .tint(AppColor.accentPrimary)
                }
            }

            ForEach(viewModel.displayedBarriers) { barrier in
                Annotation(
                    barrier.type.localizedLabel,
                    coordinate: CLLocationCoordinate2D(
                        latitude: barrier.latitude,
                        longitude: barrier.longitude
                    )
                ) {
                    BarrierAnnotation(barrier: barrier)
                        .onTapGesture { selectedBarrier = barrier }
                }
            }

            ForEach(viewModel.displayedPOIs) { poi in
                Annotation(
                    poi.name,
                    coordinate: CLLocationCoordinate2D(
                        latitude: poi.latitude,
                        longitude: poi.longitude
                    )
                ) {
                    POIMarker(poi: poi)
                        .onTapGesture { selectedPOI = poi }
                }
            }

            // Gewählter POI (Suche oder Apple-Karten-POI): immer als (leicht
            // hervorgehobener) Marker sichtbar, auch wenn er nicht unter den
            // POIs in der Nähe ist. Während einer aktiven Navigation übernimmt
            // der Ziel-Marker, deshalb hier nur ohne Route.
            if viewModel.activeRoute == nil,
               let poi = focusedPOI,
               !viewModel.displayedPOIs.contains(where: { $0.id == poi.id }) {
                Annotation(
                    poi.name,
                    coordinate: CLLocationCoordinate2D(
                        latitude: poi.latitude,
                        longitude: poi.longitude
                    )
                ) {
                    POIMarker(poi: poi)
                        .scaleEffect(1.2)
                        .shadow(color: AppColor.accentPrimary.opacity(0.5), radius: 6)
                        .onTapGesture { selectedPOI = poi }
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapScaleView()
        }
        // Direkt auf der Map, damit Hell-/Dunkel-Modus und Satellitenansicht
        // nur die Karte betreffen, nicht die Overlays.
        .mapDisplayPreferences(mapPreferences)
        // Kartendrehung mitverfolgen, damit der Blickrichtungs-Kegel am
        // Standortpunkt korrekt ausgerichtet bleibt (Navigation dreht die
        // Karte, der User kann sie zudem mit zwei Fingern drehen).
        .onMapCameraChange(frequency: .continuous) { context in
            // Nur nennenswerte Änderungen übernehmen: Der Wert steckt in einem
            // @State und löste sonst bei jeder Animationsstufe ein komplettes
            // View-Update aus.
            if abs(
                ARHeadingCorrection.normalizedSignedDegrees(context.camera.heading - mapHeading)
            ) >= 1 {
                mapHeading = context.camera.heading
            }
            // Selbst gegriffene Karte: Zoomstufe übernehmen (sie wird danach
            // nie automatisch verändert) und die automatische Kameraführung
            // kurz aussetzen, damit sie nicht gegen die Geste arbeitet.
            guard cameraPosition.positionedByUser else { return }
            navCamera.distanceM = context.camera.distance
            navCamera.pausedUntil = Date().addingTimeInterval(Self.userCameraGraceS)
        }
        .onAppear {
            viewModel.start()
        }
        // Nur EINMAL auf den Standort zentrieren (State-Flag statt `.first()`:
        // onReceive abonniert bei jedem Body-Update neu, wodurch `.first()`
        // den letzten Standort erneut liefern und den manuell gewählten
        // Zoom immer wieder zurücksetzen würde).
        .onReceive(locationService.$currentLocation.compactMap { $0 }) { location in
            guard !hasCenteredOnUser else { return }
            hasCenteredOnUser = true
            withAnimation(.easeInOut) {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: location.coordinate,
                        span: Self.closeUpSpan
                    )
                )
            }
        }
        .onReceive(locationService.$currentLocation) { _ in
            evaluateProximity()
        }
        // Während der Navigation folgt die Karte dem Standort; die Drehung
        // kommt aus der eigenen Ausrichtung (siehe updateNavigationCamera).
        .onReceive(locationService.$currentLocation.compactMap { $0 }) { _ in
            updateNavigationCamera(force: true)
        }
        // Die Karte dreht sich auch beim Drehen auf der Stelle mit – dafür
        // genügen Standort-Updates nicht, die Blickrichtung muss die Kamera
        // ebenfalls nachführen.
        .onReceive(headingUpdates) { _ in
            updateNavigationCamera()
        }
        // Neue Route (auch nach automatischer Neuberechnung): in der Übersicht
        // den Ausschnitt auf die neue Strecke anpassen, im Folgen-Modus
        // einfach weiterlaufen lassen – dort bleibt die Zoomstufe stehen.
        // Ohne Route den Kamerazustand zurücksetzen.
        .onChange(of: viewModel.activeRoute?.id) { _, newID in
            guard newID != nil, let route = viewModel.activeRoute else {
                routeCameraMode = .overview
                navCamera.reset()
                return
            }
            if routeCameraMode == .overview {
                fitCamera(to: route)
            }
        }
        .onReceive(barrierNotifications.$tappedBarrierId) { barrierId in
            guard let barrierId,
                  let barrier = viewModel.filteredBarriers.first(where: { $0.id == barrierId })
            else { return }
            barrierNotifications.tappedBarrierId = nil
            selectedBarrier = barrier
        }
        // Links oben der Ebenen-Button (Kartenmodus und Darstellung), rechts
        // oben der Kompass. Die Suche sitzt als Leiste unten am Bildschirmrand
        // – in Daumenreichweite, statt als Icon in der oberen Ecke.
        .overlay(alignment: .topLeading) {
            if viewModel.activeRoute == nil {
                mapLayersButton
                    .padding(.leading, 16)
                    .padding(.top, 16)
            }
        }
        // Banner sitzen unterhalb der Bedienzeile (Ebenen-Button links,
        // Kompass rechts), damit sie die Ecken-Buttons nicht verdecken.
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                // Fallback-Banner nur ohne Mitteilungs-Berechtigung; sonst
                // kommt die Warnung als System-Mitteilung (UserNotifications).
                if !barrierNotifications.isAuthorized,
                   let warning = proximityService.activeWarning {
                    approachBanner(warning)
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Hinweis, dass man von der Route abgekommen ist (mit
                // Status der automatischen Neuberechnung).
                if viewModel.isOffRoute {
                    offRouteBanner
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if !connectivity.isOnline {
                    OfflineOverlay()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if viewModel.isLoading {
                    ProgressView()
                        .padding(8)
                        .background(.thinMaterial, in: Capsule())
                }
                if viewModel.isCalculatingRoute {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Route wird berechnet…")
                            .font(.footnote)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                }
            }
            // Unterhalb der Bedienelemente oben (Ebenen-Button links, Kompass
            // rechts), damit die Banner sie nicht überdecken.
            .padding(.top, 68)
            .animation(.easeInOut(duration: 0.25), value: connectivity.isOnline)
            .animation(.spring(duration: 0.35), value: proximityService.activeWarning?.barrier.id)
            .animation(.spring(duration: 0.35), value: viewModel.isOffRoute)
        }
        // Persistenter Kompass (Blickrichtung des Geräts), rechts oben auf
        // Höhe des Ebenen-Buttons.
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 12) {
                CompassView(heading: locationService.heading, background: Self.controlBackground)
                // Umschalter Übersicht ⇄ Folgen, nur während der Navigation.
                if viewModel.activeRoute != nil {
                    routeCameraButton
                }
            }
            .padding(.trailing, 16)
            .padding(.top, 16)
        }
        // Bedienstapel rechts über der Suchleiste: Routen planen und zurück
        // zum eigenen Standort. Während der Navigation übernimmt das
        // Routen-Panel unten, der Stapel verschwindet.
        .overlay(alignment: .trailing) {
            if viewModel.activeRoute == nil {
                mapControlStack
                    .padding(.trailing, 16)
            }
        }
        // Suchleiste unten – der Einstieg in Suche und Filter.
        .overlay(alignment: .bottom) {
            if viewModel.activeRoute == nil {
                mapSearchBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if let route = viewModel.activeRoute {
                MapRoutePanel(
                    route: route,
                    progress: viewModel.routeProgress,
                    maneuver: viewModel.nextManeuver,
                    currentStep: currentRouteStep,
                    onShowSteps: route.steps.isEmpty ? nil : { showingRouteSteps = true },
                    barrierCount: routeBarrierCount,
                    criticalCount: criticalRouteBarrierCount,
                    onShowBarriers: { showingRouteBarriers = true },
                    onStop: { viewModel.stopNavigation() }
                )
                // Volle Breite während der Navigation: Die Karten-Bedienelemente
                // sind ausgeblendet, die Abbiege-Anweisung bekommt so mehr Platz.
                .padding(.horizontal)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: viewModel.activeRoute)
        .overlay {
            if showEmptyState {
                EmptyStateView { showingFilter = true }
            }
        }
        // Ganzflächige Zustands-Screens: Ohne Standort-Freigabe steht die
        // Karte still, ein gescheiterter Routenstart braucht eine Antwort.
        // Beide liegen über allem – sie sind der Zustand, nicht ein Hinweis.
        .overlay {
            if showLocationState {
                AppStateScreen.locationUnavailable(
                    onShowMapAnyway: { locationStateDismissed = true }
                )
                .transition(.opacity)
            } else if let failure = viewModel.routeFailure {
                AppStateScreen.routeUnavailable(
                    reason: failure.reason,
                    onRetry: { Task { await viewModel.retryFailedRoute() } },
                    onBack: { viewModel.clearRouteFailure() }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.routeFailure?.id)
        .overlay(alignment: .bottom) {
            if let error = viewModel.loadError {
                Text(error)
                    .font(.footnote)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
        .sheet(item: $selectedBarrier) { barrier in
            BarrierDetailSheet(
                barrier: barrier,
                profile: profile,
                onFindAlternative: alternativeAction(for: barrier)
            )
            .trackScreen("barrier_detail", properties: [
                "barrier_id": barrier.id.uuidString,
                "type": barrier.type.rawValue
            ])
        }
        // Barrieren-Liste zur aktiven Route; Zeilen-Tap merkt die Barriere
        // vor und öffnet ihr Detail-Sheet, sobald die Liste geschlossen ist.
        .sheet(isPresented: $showingRouteBarriers, onDismiss: {
            if let barrier = pendingListBarrier {
                pendingListBarrier = nil
                selectedBarrier = barrier
            }
        }) {
            RouteBarrierListSheet(
                entries: viewModel.routeBarrierEntries,
                profile: profile,
                avoidedBarrierIds: viewModel.avoidedBarrierIds
            ) { barrier in
                pendingListBarrier = barrier
                showingRouteBarriers = false
            }
            .trackScreen("route_barrier_list")
        }
        // Turn-by-turn-Listenansicht der aktiven Route (wo/wann/wo durch).
        .sheet(isPresented: $showingRouteSteps) {
            if let route = viewModel.activeRoute {
                RouteStepsListSheet(
                    route: route,
                    progress: viewModel.routeProgress,
                    currentStepIndex: viewModel.currentStepIndex
                )
                .trackScreen("route_steps_list")
            }
        }
        .sheet(item: $selectedPOI) { poi in
            POIDetailSheet(
                poi: poi,
                profile: profile,
                onStartARRoute: onStartARRoute,
                onShowRoute: { poi in showRoute(to: poi) }
            )
            .trackScreen("poi_detail", properties: [
                "poi_id": poi.id.uuidString,
                "name": poi.name
            ])
        }
        .sheet(isPresented: $showingSearch) {
            SearchSheet(viewModel: viewModel) { poi in
                focus(on: poi)
            }
            .trackScreen("search")
        }
        .sheet(isPresented: $showingMapSettings) {
            MapSettingsSheet(mapPreferences: mapPreferences)
                .trackScreen("map_settings")
        }
        .sheet(isPresented: $showingFilter) {
            FilterSheet(viewModel: viewModel)
                .trackScreen("filter")
        }
        // Routenplanung (Verkehrsmittel, Ziel, Wegvarianten). Eine gewählte
        // Variante startet die Navigation und zeigt die ganze Strecke.
        .sheet(isPresented: $showingRoutes) {
            RoutesSheet(viewModel: viewModel, profile: profile) { route in
                startRouteCamera(for: route)
            }
            .trackScreen("routes")
        }
    }

    // MARK: - Components

    /// Deckender weisser Hintergrund für die Karten-Bedienelemente (Suche,
    /// Karteneinstellungen, Kompass) – konsistent statt durchscheinendem
    /// Material, mit dezentem Schatten zur Abhebung von der Karte.
    private static let controlBackground = AnyShapeStyle(Color(.systemBackground))

    /// Suchleiste unten auf der Karte: Der Balken öffnet die Ortssuche, das
    /// Icon rechts den Barrierefilter. Beide Ziele sind eigene Trefferflächen,
    /// damit man den Filter nicht versehentlich mit der Suche erwischt.
    private var mapSearchBar: some View {
        HStack(spacing: 12) {
            Button {
                showingSearch = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColor.accentPrimary)
                    Text("Wohin möchtest du?")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(height: AppMetrics.Touch.primary)
                .background(AppColor.surfaceTinted, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Orte suchen")

            Button {
                showingFilter = true
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(filtersActive ? AppColor.onAccent : AppColor.accentPrimary)
                    .frame(width: AppMetrics.Touch.primary, height: AppMetrics.Touch.primary)
                    .background(
                        filtersActive
                            ? AnyShapeStyle(AppColor.accentPrimary)
                            : AnyShapeStyle(AppColor.surfaceTinted),
                        in: Circle()
                    )
            }
            .accessibilityLabel("Filter")
            .accessibilityAddTraits(filtersActive ? .isSelected : [])
        }
        .padding(8)
        .background(
            Self.controlBackground,
            in: RoundedRectangle(cornerRadius: AppMetrics.Radius.sheet + 12, style: .continuous)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }

    /// Ob aktuell ein Filter greift (für die Hervorhebung des Filter-Icons):
    /// Orte oder Barrieren ausgeblendet, oder nicht alle Barrieretypen aktiv.
    private var filtersActive: Bool {
        !viewModel.poisVisible
            || !viewModel.barriersVisible
            || viewModel.filterState.enabledTypes.count != BarrierType.allCases.count
    }

    /// Bedienstapel rechts: Routen planen und auf den eigenen Standort
    /// zentrieren – die zwei Aktionen, die man ohne laufende Route braucht.
    private var mapControlStack: some View {
        VStack(spacing: 0) {
            Button {
                showingRoutes = true
            } label: {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Route planen")

            Divider().frame(width: 30)

            Button {
                centerOnUser()
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        locationService.currentLocation == nil
                            ? AppColor.textSecondary
                            : AppColor.accentPrimary
                    )
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .disabled(locationService.currentLocation == nil)
            .accessibilityLabel("Auf meinen Standort zentrieren")
        }
        .background(
            Self.controlBackground,
            in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
        )
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }

    /// Ebenen-Button links oben: öffnet Kartenmodus und Darstellung.
    private var mapLayersButton: some View {
        Button {
            showingMapSettings = true
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 44, height: 44)
                .background(Self.controlBackground, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        }
        .accessibilityLabel("Karteneinstellungen")
    }

    /// Karte zurück auf den eigenen Standort holen (Bedienstapel rechts).
    private func centerOnUser() {
        guard let location = locationService.currentLocation else { return }
        withAnimation(.easeInOut) {
            cameraPosition = .region(
                MKCoordinateRegion(center: location.coordinate, span: Self.closeUpSpan)
            )
        }
    }

    /// Wechselt zwischen Übersicht (ganze Route im Bild) und Folgen (Karte
    /// folgt dem Standort und dreht sich mit der eigenen Ausrichtung mit).
    private var routeCameraButton: some View {
        Button {
            switch routeCameraMode {
            case .overview:
                // Zurück aus der Übersicht: wieder auf den Standort zoomen,
                // sonst bliebe der weite Übersichts-Zoom stehen.
                routeCameraMode = .following
                navCamera.pausedUntil = nil
                navCamera.distanceM = Self.defaultRouteCameraDistanceM
                updateNavigationCamera(force: true)
            case .following:
                routeCameraMode = .overview
                navCamera.pausedUntil = nil
                if let route = viewModel.activeRoute {
                    fitCamera(to: route, force: true)
                }
            }
        } label: {
            Image(systemName: routeCameraMode == .overview
                  ? "location.fill"
                  : "arrow.up.left.and.arrow.down.right")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 44, height: 44)
                .background(Self.controlBackground, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        }
        .accessibilityLabel(routeCameraMode == .overview
                            ? "Standort folgen"
                            : "Ganze Route anzeigen")
    }


    // Banner ~30 m vor profilrelevanter Barriere.
    // Tap → Detail-Sheet, X oder Wegswipen → dismiss. Bleibt bewusst stehen,
    // bis es weggewischt wird (kein automatisches Ausblenden) – so verpasst
    // man die Warnung nicht (Feldtest-Rückmeldung Tag 1).
    private func approachBanner(_ warning: BarrierWarning) -> some View {
        Button {
            selectedBarrier = warning.barrier
            proximityService.dismissCurrent()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.square")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(warning.barrierValue) in \(Int(warning.distance)) m voraus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Tippen für Details · Wegwischen zum Ausblenden")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    proximityService.dismissCurrent()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .accessibilityLabel("Warnung ausblenden")
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 4)
        }
        .buttonStyle(.plain)
        .swipeToDismiss { proximityService.dismissCurrent() }
    }

    /// Hinweis, dass man von der Route abgekommen ist. Der Untertitel zeigt,
    /// was gerade passiert (Neuberechnung läuft / geplant / offline nicht
    /// möglich). Blendet sich automatisch aus, sobald man wieder auf Kurs ist.
    private var offRouteBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Du bist von der Route abgekommen")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(offRouteSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isRerouting {
                ProgressView()
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Du bist von der Route abgekommen. \(offRouteSubtitle)")
    }

    private var offRouteSubtitle: String {
        if viewModel.isRerouting { return "Route wird angepasst…" }
        if !connectivity.isOnline { return "Kein Netz – bisherige Route bleibt" }
        return "Route wird neu berechnet"
    }

    // MARK: - Helpers

    /// Kamera-Blickrichtung des Geräts relativ zur aktuellen Kartendrehung –
    /// so zeigt der Kegel am Standortpunkt auch bei gedrehter Karte UND bei
    /// aufrecht gehaltenem iPhone dorthin, wohin die Kamera tatsächlich schaut.
    /// `nil`, solange keine Richtung vorliegt.
    private var userConeHeading: CLLocationDirection? {
        locationService.viewingDirection.map { $0 - mapHeading }
    }

    /// Route aufgeteilt in "schon gefahren" und "liegt noch vor mir" – der
    /// Standort wird dabei auf dieselbe Stelle projiziert wie für Restweg und
    /// Abbiege-Ansage (gleicher Fortschritts-Anker). Ohne Standort-Fix gilt
    /// die ganze Route als bevorstehend.
    private func routeParts(
        of route: ActiveRoute
    ) -> (covered: [CLLocationCoordinate2D], remaining: [CLLocationCoordinate2D]) {
        guard let location = locationService.currentLocation else {
            return ([], route.coordinates)
        }
        return RouteService.split(
            route,
            at: location.coordinate,
            alongAnchorM: viewModel.routeAnchorAlongM
        )
    }

    /// Maximaler seitlicher Abstand (Meter), bis zu dem der Standortpunkt
    /// während der Navigation auf die Route eingerastet wird. Darüber hinaus
    /// (der User folgt der Route offenbar nicht) zeigt der Punkt die echte
    /// Position – dann greift ohnehin die automatische Neuberechnung.
    private static let snapToRouteMaxOffsetM: CLLocationDistance = 12

    /// Standortkoordinate für den Karten-Marker: während der Navigation auf die
    /// Route (violette Linie) eingerastet, solange man nah genug an ihr ist –
    /// so springt der Punkt nicht mehr neben der Linie herum (GPS-Rauschen in
    /// den engen Gassen). Ohne aktive Route die Rohposition. Das Einrasten
    /// läuft über das ViewModel, damit es denselben Fortschritts-Anker nutzt
    /// wie Restweg und Abbiege-Ansage (sonst könnte der Punkt auf dem
    /// Rückweg-Ast einer Route einrasten, die dicht an sich vorbeiführt).
    private func snappedUserCoordinate(for location: CLLocation) -> CLLocationCoordinate2D {
        viewModel.snappedCoordinate(for: location, maxOffsetM: Self.snapToRouteMaxOffsetM)
    }

    /// "Route anzeigen" aus dem POI-Detail: Route in-App berechnen und den
    /// ganzen Weg zeigen – vom eigenen Standort bis zum Ziel.
    private func showRoute(to poi: POI) {
        Task {
            guard await viewModel.startNavigation(to: poi, profile: profile),
                  let route = viewModel.activeRoute else { return }
            startRouteCamera(for: route)
        }
    }

    /// Kamerazustand für eine frisch gestartete Route: die ganze Strecke im
    /// freien Bereich zwischen den Bedienelementen und dem Routen-Panel.
    /// Bewusst nur bei einer vom User gestarteten Route – eine automatische
    /// Neuberechnung soll den Ausschnitt nicht zurücksetzen, den er
    /// inzwischen selbst gewählt hat.
    private func startRouteCamera(for route: ActiveRoute) {
        routeCameraMode = .overview
        navCamera.reset()
        fitCamera(to: route, force: true)
    }

    /// Kameraabstand je Meter Ausdehnung der Route. Sichtbar ist nur der freie
    /// Streifen zwischen den Bedienelementen oben und dem Routen-Panel plus
    /// Tab-Leiste unten – gut die Hälfte der Bildhöhe. Der Faktor sorgt dafür,
    /// dass die Route in DIESEN Streifen passt, nicht bloss auf den Schirm,
    /// und zwar in jeder Drehlage (die Karte dreht sich ja mit).
    private static let routeOverviewDistanceFactor = 3.8
    /// Untergrenze des Kameraabstands, damit sehr kurze Routen nicht
    /// übermässig herangezoomt werden.
    private static let routeOverviewMinDistanceM: CLLocationDistance = 320
    /// Anteil des Kameraabstands, um den der Ausschnitt entgegen der
    /// Blickrichtung verschoben wird. Das Panel unten ist deutlich höher als
    /// die Bedienzeile oben, der freie Bereich liegt also über der Bildmitte;
    /// die Verschiebung rückt die Route dort hinein. Bewusst am Kameraabstand
    /// bemessen und nicht an der Routenlänge – verdeckt wird immer derselbe
    /// ANTEIL des Bildes, unabhängig davon, wie lang die Strecke ist.
    private static let routeOverviewBottomBias = 0.10

    /// Passt den Kartenausschnitt auf die KOMPLETTE Route ein – vom eigenen
    /// Standort bis zum Ziel, im freien Bereich zwischen den Bedienelementen
    /// oben und dem Routen-Panel unten.
    ///
    /// Der eigene Standort geht bewusst in den Ausschnitt ein: Steht man neben
    /// der Route (oder ist sie noch vom alten Startpunkt gerechnet), soll man
    /// trotzdem sehen, wo man selbst ist.
    ///
    /// Der so bestimmte Abstand wird als Zoomstufe für den Folgen-Modus
    /// übernommen – wechselt man dorthin, springt die Karte also nicht
    /// ungefragt näher heran.
    private func fitCamera(to route: ActiveRoute, force: Bool = false) {
        // Pro Route nur einmal einpassen (mehrere Auslöser: "Route anzeigen",
        // Neuberechnung, Alternativroute); der Übersichts-Button erzwingt es.
        guard force || navCamera.fittedRouteID != route.id else { return }
        navCamera.fittedRouteID = route.id

        var points = route.coordinates
        if let location = locationService.currentLocation {
            points.append(location.coordinate)
        }
        guard let first = points.first else { return }

        var minLat = first.latitude, maxLat = first.latitude
        var minLng = first.longitude, maxLng = first.longitude
        for point in points {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLng = min(minLng, point.longitude)
            maxLng = max(maxLng, point.longitude)
        }

        let boundingBoxCenter = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )

        // Ausdehnung in Metern (Diagonale der Bounding-Box), damit der
        // gewählte Abstand die Route in jeder Drehlage abdeckt.
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(boundingBoxCenter.latitude * .pi / 180)
        let widthM = (maxLng - minLng) * metersPerDegreeLongitude
        let heightM = (maxLat - minLat) * metersPerDegreeLatitude
        let diagonalM = (widthM * widthM + heightM * heightM).squareRoot()

        let distance = max(
            diagonalM * Self.routeOverviewDistanceFactor,
            Self.routeOverviewMinDistanceM
        )

        navCamera.overviewCenter = boundingBoxCenter
        navCamera.overviewOffsetM = distance * Self.routeOverviewBottomBias
        // Zoomstufe der Übersicht auch als Folgen-Zoom übernehmen: Der Wechsel
        // in den Folgen-Modus zoomt dadurch nicht automatisch näher heran.
        navCamera.distanceM = distance

        applyNavigationCamera(force: true)
    }

    /// Zoomstufe im Folgen-Modus (Kameraabstand in Metern): nah genug für die
    /// nächsten Gassen, weit genug für den übernächsten Abbieger. Danach
    /// zählt immer die zuletzt eingestellte Stufe.
    private static let defaultRouteCameraDistanceM: CLLocationDistance = 250
    /// So lange bleibt die automatische Kameraführung nach einer eigenen
    /// Kartengeste stehen, damit sie nicht gegen die Hand arbeitet.
    private static let userCameraGraceS: TimeInterval = 8
    /// Mindestabstand zwischen zwei Kamera-Nachführungen (die Blickrichtung
    /// kommt mit ~20 Hz).
    private static let cameraUpdateIntervalS: TimeInterval = 0.25
    /// Ab dieser Richtungsänderung (Grad) wird die Karte nachgedreht – kleinere
    /// Zappler bleiben unbeachtet, damit das Bild ruhig steht.
    private static let cameraHeadingStepDeg: Double = 2

    /// Blickrichtungs-Updates (Kompass und – aufrecht gehalten – die aus der
    /// Gerätelage bestimmte Kamerarichtung), auf die die Kartendrehung reagiert.
    private var headingUpdates: AnyPublisher<CLLocationDirection?, Never> {
        Publishers.Merge(locationService.$heading, locationService.$lookDirection)
            .eraseToAnyPublisher()
    }

    /// Nachführen der Kamera während der Navigation – gedrosselt und nur bei
    /// nennenswerter Änderung, damit das Kartenbild ruhig bleibt.
    private func updateNavigationCamera(force: Bool = false) {
        guard viewModel.activeRoute != nil else { return }
        applyNavigationCamera(force: force)
    }

    /// Setzt die Kamera für den aktuellen Modus:
    ///
    /// – In BEIDEN Modi dreht sich die Karte mit der EIGENEN Ausrichtung mit,
    ///   die Route liegt also immer so im Bild, wie sie vor einem liegt.
    ///   Ohne Blickrichtung (Gerät flach) zählt ersatzweise die Fahrtrichtung
    ///   der Route.
    /// – Übersicht: Zentrum auf der Route, ganze Strecke im Bild.
    /// – Folgen: Zentrum am eigenen Standort, etwas nach vorn versetzt.
    ///
    /// Die Zoomstufe wird dabei NIE automatisch verändert: Es zählt die zuletzt
    /// vom User eingestellte bzw. die beim Einpassen der ganzen Route
    /// ermittelte Stufe. `force` (Standort-Update, Moduswechsel, neues
    /// Einpassen) übergeht die Drosselung.
    private func applyNavigationCamera(force: Bool) {
        let now = Date()
        if let pausedUntil = navCamera.pausedUntil {
            guard now >= pausedUntil else { return }
            navCamera.pausedUntil = nil
        }
        if !force,
           let last = navCamera.lastUpdateAt,
           now.timeIntervalSince(last) < Self.cameraUpdateIntervalS { return }

        let location = locationService.currentLocation
        guard let heading = navigationHeading(at: location) else { return }
        if !force,
           let applied = navCamera.appliedHeadingDeg,
           abs(ARHeadingCorrection.normalizedSignedDegrees(heading - applied))
            < Self.cameraHeadingStepDeg { return }

        let distance = navCamera.distanceM ?? Self.defaultRouteCameraDistanceM
        guard let center = navigationCenter(heading: heading, distance: distance, at: location)
        else { return }

        navCamera.lastUpdateAt = now
        navCamera.appliedHeadingDeg = heading

        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: center,
                    distance: distance,
                    heading: heading,
                    pitch: 0
                )
            )
        }
    }

    /// Kartenzentrum für den aktuellen Modus (siehe `applyNavigationCamera`).
    private func navigationCenter(
        heading: CLLocationDirection,
        distance: CLLocationDistance,
        at location: CLLocation?
    ) -> CLLocationCoordinate2D? {
        switch routeCameraMode {
        case .overview:
            guard let base = navCamera.overviewCenter else { return nil }
            // Entgegen der Blickrichtung versetzt, damit die Route über dem
            // Routen-Panel im freien Bereich liegt.
            return Self.coordinate(
                from: base,
                distanceM: navCamera.overviewOffsetM ?? 0,
                bearingDeg: (heading + 180).truncatingRemainder(dividingBy: 360)
            )
        case .following:
            guard let location else { return nil }
            // Zentrum etwas in Blickrichtung versetzen, damit der eigene
            // Standort im unteren Drittel sitzt und mehr Strecke voraus
            // sichtbar ist – proportional zum Zoom, damit es in jeder Stufe passt.
            return Self.coordinate(
                from: snappedUserCoordinate(for: location),
                distanceM: min(distance * 0.15, 90),
                bearingDeg: heading
            )
        }
    }

    /// Geglättete Richtung, in die die Karte gedreht wird: bevorzugt die eigene
    /// Blickrichtung, ersatzweise die Fahrtrichtung der Route. Die Glättung
    /// nimmt dem Kompass die Zappler, ohne Verzögerung spürbar zu machen.
    private func navigationHeading(at location: CLLocation?) -> CLLocationDirection? {
        var target = locationService.viewingDirection
        if target == nil, let location, let route = viewModel.activeRoute {
            target = RouteService.travelBearingDegrees(
                of: route,
                at: location,
                alongAnchorM: viewModel.routeAnchorAlongM
            )
        }
        if target == nil, let route = viewModel.activeRoute {
            target = RouteService.initialBearingDegrees(of: route)
        }
        guard let target else { return nil }

        let smoothed = ARHeadingCorrection.smooth(
            previous: navCamera.smoothedHeadingDeg,
            new: target,
            factor: 0.3
        )
        navCamera.smoothedHeadingDeg = smoothed
        return (smoothed + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Koordinate, die `distanceM` Meter in Kompassrichtung `bearingDeg`
    /// (0 = Nord) vom Ursprung entfernt liegt (Flach-Erde-Näherung).
    private static func coordinate(
        from origin: CLLocationCoordinate2D,
        distanceM: Double,
        bearingDeg: Double
    ) -> CLLocationCoordinate2D {
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(origin.latitude * .pi / 180)
        let radians = bearingDeg * .pi / 180
        return CLLocationCoordinate2D(
            latitude: origin.latitude + cos(radians) * distanceM / metersPerDegreeLatitude,
            longitude: origin.longitude + sin(radians) * distanceM / metersPerDegreeLongitude
        )
    }

    /// Aktueller Schritt der aktiven Route (Strasse "wo durch" fürs Panel).
    private var currentRouteStep: RouteStep? {
        guard let route = viewModel.activeRoute,
              let index = viewModel.currentStepIndex,
              route.steps.indices.contains(index) else { return nil }
        return route.steps[index]
    }

    /// Barrieren im Korridor der aktiven Route (für die Zähler-Zeile im
    /// Routen-Panel).
    private var routeBarrierCount: Int {
        viewModel.routeBarrierEntries.count
    }

    /// Davon fürs eigene Profil kritisch (shouldWarn).
    private var criticalRouteBarrierCount: Int {
        viewModel.routeBarrierEntries
            .filter { shouldWarn(barrier: $0.barrier, profile: profile) }
            .count
    }

    /// Alternativroute-Aktion fürs Barrieren-Detail – nur während einer
    /// aktiven Navigation, sonst nil (Sektion bleibt ausgeblendet).
    private func alternativeAction(for barrier: Barrier) -> AlternativeRouteAction? {
        guard viewModel.activeRoute != nil else { return nil }
        return AlternativeRouteAction { await findAlternativeRoute(avoiding: barrier) }
    }

    /// "Alternativroute anzeigen" aus dem Barrieren-Detail: Route neu
    /// berechnen, so dass sie die Barriere umgeht (Tagesform, z. B. Hitze),
    /// und bei Erfolg auf den neuen Routenverlauf zoomen.
    @MainActor
    private func findAlternativeRoute(avoiding barrier: Barrier) async -> Bool {
        let success = await viewModel.findAlternativeRoute(avoiding: barrier, profile: profile)
        if success, let route = viewModel.activeRoute {
            // Wie beim Routenstart: den neuen Weg in ganzer Länge zeigen –
            // der Umweg soll beurteilbar sein, bevor man ihm folgt.
            startRouteCamera(for: route)
        }
        return success
    }

    private func focus(on poi: POI) {
        withAnimation(.easeInOut) {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
                )
            )
        }
        focusedPOI = poi
        selectedPOI = poi
    }

    /// Apple-Karten-POI (MapFeature) übernehmen: in einen leichten POI wandeln
    /// (Distanz zum Standort ergänzt), als Marker hervorheben und das
    /// Detail-Sheet öffnen.
    private func selectAppleFeature(_ feature: MapFeature) {
        let distance = locationService.currentLocation.map {
            CLLocation(latitude: feature.coordinate.latitude, longitude: feature.coordinate.longitude)
                .distance(from: $0)
        } ?? 0
        let poi = POI(appleFeature: feature, distanceM: distance)
        focusedPOI = poi
        selectedPOI = poi
    }

    /// Karte samt Inhalt. Ab iOS 18 mit Auswahl der built-in Apple-POIs
    /// (MapFeature); auf iOS 17 ohne diese (die API `MapSelection` gibt es erst
    /// ab iOS 18) – der Rest der Karte bleibt identisch. Der Kartinhalt wird an
    /// beide Zweige übergeben, damit er nur einmal beschrieben ist.
    @ViewBuilder
    private func mapContainer<C: MapContent>(
        @MapContentBuilder content: () -> C
    ) -> some View {
        if #available(iOS 18.0, *) {
            Map(position: $cameraPosition, selection: appleSelectionBinding) {
                content()
            }
            // Nur Apples Points of Interest sind auswählbar (keine Regionen).
            .mapFeatureSelectionDisabled { $0.kind != .pointOfInterest }
        } else {
            Map(position: $cameraPosition) {
                content()
            }
        }
    }

    /// Auswahl-Binding für Apple-Karten-POIs (nur iOS 18+). Die Auswahl wird
    /// nicht gehalten: Beim Tippen auf ein POI-Feature wird es direkt in einen
    /// POI gewandelt und das Detail-Sheet geöffnet (getter bleibt `nil`, damit
    /// kein System-Callout stehen bleibt und ein erneuter Tap wieder auslöst).
    @available(iOS 18.0, *)
    private var appleSelectionBinding: Binding<MapSelection<MKMapItem>?> {
        Binding(
            get: { nil },
            set: { newValue in
                if let feature = newValue?.feature {
                    selectAppleFeature(feature)
                }
            }
        )
    }

    private func evaluateProximity() {
        proximityService.evaluate(
            userLocation: locationService.currentLocation,
            barriers: viewModel.filteredBarriers,
            profile: profile
        )
    }

    /// Standort dauerhaft verweigert (der System-Dialog kommt nicht wieder) –
    /// solange der Zustands-Screen nicht bewusst weggetippt wurde.
    private var showLocationState: Bool {
        guard !locationStateDismissed else { return false }
        switch locationService.authorizationStatus {
        case .denied, .restricted: return true
        default: return false
        }
    }

    private var showEmptyState: Bool {
        !viewModel.isLoading
            && viewModel.loadError == nil
            // Kein Empty-State, wenn die Karte nur wegen der
            // Sichtbarkeits-Toggles leer ist – das ist gewollt.
            && viewModel.barriersVisible
            && viewModel.poisVisible
            && viewModel.filteredBarriers.isEmpty
            && viewModel.displayedPOIs.isEmpty
            && locationService.currentLocation != nil
    }
}

/// Laufende Zwischenwerte der Navigations-Kameraführung. Bewusst ein
/// Referenztyp in `@State`: Geglättete Richtung, Drosselung und Zoomstufe
/// ändern sich mehrmals pro Sekunde und sollen dabei KEIN SwiftUI-Update
/// auslösen (nur die Kameraposition selbst tut das).
final class NavigationCameraState {
    /// Geglättete Blickrichtung (signierte Grad), Basis der Kartendrehung.
    var smoothedHeadingDeg: CLLocationDirection?
    /// Zuletzt an die Kamera übergebene Drehung (0–360°).
    var appliedHeadingDeg: CLLocationDirection?
    /// Zeitpunkt der letzten Kamera-Nachführung (Drosselung).
    var lastUpdateAt: Date?
    /// Bis dahin bleibt die automatische Führung nach einer eigenen
    /// Kartengeste stehen.
    var pausedUntil: Date?
    /// Aktuelle Zoomstufe (Kameraabstand in Metern) – wird nur durch eigene
    /// Gesten oder das Einpassen der ganzen Route gesetzt, nie automatisch.
    var distanceM: CLLocationDistance?
    /// Mittelpunkt der eingepassten Route (Übersichtsmodus).
    var overviewCenter: CLLocationCoordinate2D?
    /// Versatz des Übersichts-Zentrums entgegen der Blickrichtung, damit die
    /// Route über dem Routen-Panel frei liegt.
    var overviewOffsetM: CLLocationDistance?
    /// Route, deren Verlauf zuletzt eingepasst wurde (verhindert doppeltes
    /// Einpassen bei mehreren Auslösern).
    var fittedRouteID: UUID?

    func reset() {
        smoothedHeadingDeg = nil
        appliedHeadingDeg = nil
        lastUpdateAt = nil
        pausedUntil = nil
        distanceM = nil
        overviewCenter = nil
        overviewOffsetM = nil
        fittedRouteID = nil
    }
}

/// Kreisförmiger POI-Marker: weisser Ring, innerer Kreis in Violett 700
/// (eine Stufe heller als das Akzent-Violett) mit dem Kategorie-Icon
/// (Restaurant, Café, WC …). Der Zugänglichkeits-Status sitzt als kleines
/// Symbol-Icon (Häkchen/Warndreieck/Kreuz) oben rechts am Ring.
struct POIMarker: View {
    let poi: POI

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 34, height: 34)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                Circle()
                    .fill(AppColor.Violet.v700)
                    .frame(width: 26, height: 26)
                Image(systemName: poi.categorySymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }

            POIStatusIcon(status: poi.accessStatus, diameter: 15)
                .offset(x: 3, y: -3)
        }
        .accessibilityLabel("\(poi.name), \(poi.accessStatus.shortLabel)")
    }
}