// MapViewModel.swift
// ARMikronav
//
// Verbindet LocationService und BarrierRepository für die Kartenansicht.
// POIs und Barrieren werden für die ganze Zürcher Altstadt geladen
// (AppConfig.altstadtCenter/-RadiusM), unabhängig vom Standort – ein
// einmaliger Ladevorgang deckt die ganze Altstadt ab. Bei aktiver
// Route werden nur noch die Barrieren direkt auf der Route angezeigt.

import Foundation
import Combine
import CoreLocation

@MainActor
final class MapViewModel: ObservableObject {
    @Published private(set) var barriers: [Barrier] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?
    @Published private(set) var filterState: BarrierFilterState = .default

    // Sichtbarkeits-Toggles (Karte & AR): blenden Barrieren- bzw. POI-Marker
    // komplett aus. Rein visuell – Annäherungswarnungen laufen weiterhin über
    // filteredBarriers, damit ausgeblendete Barrieren trotzdem warnen.
    @Published var barriersVisible = true
    @Published var poisVisible = true

    // POIs (Wireframe 2.1/2.1a): standardmässig alle POIs der Altstadt
    // (einmalig geladen). Kategorie-Chips filtern diese Liste client-seitig
    // über die exakten ginto-Kategorie-Keys; nur die Freitext-Suche läuft
    // über die RPC.
    @Published private(set) var altstadtPOIs: [POI] = []
    /// Ergebnis der letzten Freitext-Suche (nil = keine aktive Suche).
    @Published private(set) var searchResults: [POI]?
    /// Aktiver Kategorie-Chip (deutsches Label, siehe POICategory.chips).
    @Published private(set) var activeCategory: String?
    @Published private(set) var recentSearches: [String] = []

    // Navigation: aktive rollstuhlgerechte Route zu einem POI plus
    // fortlaufend aktualisierter Fortschritt (Restdistanz/Restzeit).
    @Published private(set) var activeRoute: ActiveRoute?
    @Published private(set) var routeProgress: RouteProgress?
    /// Nächstes Abbiege-Manöver (Pfeil-Anweisung) auf der aktiven Route.
    @Published private(set) var nextManeuver: RouteManeuver?
    @Published private(set) var isCalculatingRoute = false
    /// Läuft gerade eine automatische Neuberechnung, weil der User von der
    /// Route abgewichen ist? (Für einen dezenten Hinweis in der UI.)
    @Published private(set) var isRerouting = false
    /// True, sobald der User bestätigt neben der Route fährt – für den
    /// Hinweis "Du bist von der Route abgekommen" (auch offline, wenn keine
    /// Neuberechnung möglich ist).
    @Published private(set) var isOffRoute = false
    /// Ziel-POI der aktiven Navigation (nil, wenn keine Route läuft).
    @Published private(set) var navigationTarget: POI?
    /// Barrieren, die der User für heute als "nicht machbar" markiert hat
    /// (Tagesform, z. B. Hitze) – die Route wird um sie herum berechnet.
    @Published private(set) var avoidedBarrierIds: Set<UUID> = []

    /// Profil der aktiven Navigation – für die automatische Neuberechnung
    /// (Rollstuhl-Limits) gemerkt, solange eine Route läuft.
    private var navigationProfile: UserProfile?
    /// Aufeinanderfolgende Standort-Updates, in denen der User zu weit neben
    /// der Route lag (Entprellung gegen GPS-Ausreisser).
    private var offRouteUpdates = 0
    /// Zeitpunkt der letzten automatischen Neuberechnung (Sperrzeit dazwischen).
    private var lastRerouteAt: Date?

    /// Seitlicher Abstand zur Route, ab dem als "nicht auf der Route" gilt.
    private let offRouteThresholdM: CLLocationDistance = 25
    /// So viele Updates in Folge über der Schwelle lösen die Neuberechnung aus.
    private let offRouteConfirmations = 3
    /// Mindestabstand zwischen zwei automatischen Neuberechnungen.
    private let minRerouteInterval: TimeInterval = 12

    private let locationService: LocationService
    private let repository: BarrierRepository
    private let poiRepository: POIRepository
    private let recentSearchesKey = "armikronav.recentSearches"

    private var cancellables = Set<AnyCancellable>()
    private var hasStarted = false

    var filteredBarriers: [Barrier] {
        barriers.filter { filterState.enabledTypes.contains($0.type) }
    }

    /// Halbe Korridor-Breite: nur Barrieren, die höchstens so weit neben dem
    /// Routen-Polyline liegen, gelten als "auf der Route" und werden angezeigt.
    /// Bewusst eng (6 m), damit in der Altstadt keine Barrieren von parallelen
    /// Gassen mitgezählt werden – Häuserblöcke sind dort nur ~20–30 m tief,
    /// ein breiter Korridor würde die Nachbargasse einschliessen. Gilt für
    /// Karte, Listenansicht UND Alternativroute (alle über `activeRoute`).
    private let routeCorridorM: CLLocationDistance = 6

    /// Barrieren, die auf der Karte/AR angezeigt werden:
    /// – Barrieren per Toggle ausgeblendet → keine
    /// – aktive Route → nur Barrieren im Korridor direkt entlang der Route,
    ///   co-lokalisierte zu EINER Stelle zusammengefasst (siehe unten)
    /// – sonst → nur profilrelevante Barrieren im engen Umkreis des Standorts
    ///   (nearbyDisplayRadiusM), co-lokalisierte zusammengefasst
    var displayedBarriers: [Barrier] {
        guard barriersVisible else { return [] }
        if let route = activeRoute {
            let onRoute = filteredBarriers.filter { barrier in
                RouteService.distance(
                    from: CLLocationCoordinate2D(
                        latitude: barrier.latitude,
                        longitude: barrier.longitude
                    ),
                    to: route
                ) <= routeCorridorM
            }
            return collapseColocated(onRoute)
        }
        // Ohne Route nur die Barrieren im engen Umkreis des aktuellen
        // Standorts anzeigen (Überlastung vermeiden); passt sich beim
        // Weiterfahren an.
        return collapseColocated(nearCurrentLocation(filteredBarriers) {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        })
    }

    /// Filtert Elemente auf den Anzeige-Umkreis (nearbyDisplayRadiusM) um den
    /// aktuellen Standort. Bewusst eng, damit in der dichten Altstadt nur die
    /// unmittelbare Umgebung sichtbar ist (Feldtest-Rückmeldung Tag 1). Ohne
    /// Standort-Fix (kurz nach dem Start) werden übergangsweise alle Elemente
    /// gezeigt. `location` liefert die Position je Element.
    private func nearCurrentLocation<Element>(
        _ elements: [Element],
        location: (Element) -> CLLocation
    ) -> [Element] {
        guard let userLocation = locationService.currentLocation else { return elements }
        return elements.filter { element in
            userLocation.distance(from: location(element)) <= AppConfig.nearbyDisplayRadiusM
        }
    }

    /// Fasst Barrieren am exakt selben Punkt zu EINER Stelle zusammen –
    /// im OSM-Import tragen viele Wegknoten mehrere Barriere-Tags gleichzeitig
    /// (z. B. abgesenkter Bordstein + Steigung + Oberfläche). Auf der Karte
    /// stapeln sich diese zu einem einzigen sichtbaren Marker, während die
    /// Liste sonst jede einzeln zählen würde (8 Marker vs. 15 Listeneinträge).
    /// Pro Punkt bleibt die schwerwiegendste Barriere als Stellvertreterin –
    /// so zeigen Karte, Liste und der Panel-Zähler exakt dieselbe Anzahl.
    private func collapseColocated(_ barriers: [Barrier]) -> [Barrier] {
        var representatives: [String: Barrier] = [:]
        for barrier in barriers {
            // 6 Nachkommastellen ≈ 0,11 m: fasst nur wirklich deckungsgleiche
            // Punkte zusammen, keine benachbarten Barrieren.
            let key = String(format: "%.6f,%.6f", barrier.latitude, barrier.longitude)
            if let current = representatives[key], !barrier.isMoreSevere(than: current) {
                continue
            }
            representatives[key] = barrier
        }
        return Array(representatives.values)
    }

    /// Eine Barriere entlang der aktiven Route für die Listenansicht:
    /// Position auf der Route (ab Start) und Restweg ab aktuellem Standort.
    struct RouteBarrierEntry: Identifiable {
        let barrier: Barrier
        /// Weglänge vom Routen-Start bis zur Barriere.
        let distanceFromStartM: CLLocationDistance
        /// Weglänge vom aktuellen Standort bis zur Barriere
        /// (negativ = bereits passiert, nil = Standort unbekannt).
        let distanceAheadM: CLLocationDistance?

        var id: UUID { barrier.id }
    }

    /// Barrieren im Korridor der aktiven Route, sortiert in Laufrichtung –
    /// die Datenbasis der "Barrieren auf der Route"-Liste.
    var routeBarrierEntries: [RouteBarrierEntry] {
        guard let route = activeRoute else { return [] }
        let alongUser = locationService.currentLocation.map {
            RouteService.distanceAlongRoute(to: $0.coordinate, on: route)
        }
        return displayedBarriers
            .map { barrier in
                let along = RouteService.distanceAlongRoute(
                    to: CLLocationCoordinate2D(
                        latitude: barrier.latitude,
                        longitude: barrier.longitude
                    ),
                    on: route
                )
                return RouteBarrierEntry(
                    barrier: barrier,
                    distanceFromStartM: along,
                    distanceAheadM: alongUser.map { along - $0 }
                )
            }
            .sorted { $0.distanceFromStartM < $1.distanceFromStartM }
    }

    /// POIs, die auf der Karte/AR angezeigt werden:
    /// – aktive Navigation → nur noch das Ziel (auch bei ausgeblendeten POIs,
    ///   damit das Navigationsziel immer sichtbar bleibt)
    /// – POIs per Toggle ausgeblendet → keine
    /// – aktive Freitext-Suche → deren Treffer (bewusst NICHT auf den Umkreis
    ///   beschränkt: eine gezielte Suche soll auch entfernte Treffer zeigen)
    /// – aktiver Kategorie-Chip → Kategorie-POIs im engen Umkreis
    /// – sonst → POIs im engen Umkreis des Standorts (nearbyDisplayRadiusM)
    var displayedPOIs: [POI] {
        if activeRoute != nil {
            return navigationTarget.map { [$0] } ?? []
        }
        guard poisVisible else { return [] }
        if let searchResults {
            return searchResults
        }
        if let activeCategory {
            return poisNearCurrentLocation(poisForCategory(activeCategory))
        }
        return poisNearCurrentLocation(altstadtPOIs)
    }

    /// POIs im Anzeige-Umkreis (nearbyDisplayRadiusM) um den aktuellen
    /// Standort – dieselbe enge Begrenzung wie bei den Barrieren, damit Karte
    /// und AR-Modus nur die unmittelbare Umgebung zeigen.
    private func poisNearCurrentLocation(_ pois: [POI]) -> [POI] {
        nearCurrentLocation(pois) {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    /// Alle Altstadt-POIs eines Kategorie-Chips (exaktes Key-Matching),
    /// nach Distanz sortiert – auch die Datenbasis der Ergebnisliste
    /// im SearchSheet.
    func poisForCategory(_ label: String) -> [POI] {
        guard let chip = POICategory.chip(forLabel: label) else { return [] }
        return altstadtPOIs
            .filter { chip.matches(category: $0.category) }
            .sorted { $0.distanceM < $1.distanceM }
    }

    init() {
        self.locationService = .shared
        self.repository = .shared
        self.poiRepository = .shared
        loadRecentSearches()
    }

    init(locationService: LocationService, repository: BarrierRepository, poiRepository: POIRepository) {
        self.locationService = locationService
        self.repository = repository
        self.poiRepository = poiRepository
        loadRecentSearches()
    }

    func applyFilter(_ newFilter: BarrierFilterState) {
        // POIs und Barrieren decken immer die ganze Altstadt ab; der
        // Filter steuert nur, welche Barrierentypen auf der Karte erscheinen.
        filterState = newFilter
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        Task { await loadBarriers() }
        Task { await loadPOIs() }

        locationService.startUpdating()

        locationService.$currentLocation
            .compactMap { $0 }
            .removeDuplicates { lhs, rhs in
                lhs.distance(from: rhs) < 1
            }
            .sink { [weak self] location in
                self?.handleLocationUpdate(location)
            }
            .store(in: &cancellables)

        // Blickrichtungs-Updates: die Abbiege-Anweisung ist egozentrisch
        // (relativ zur Blickrichtung), muss sich also auch beim Drehen auf der
        // Stelle aktualisieren – nicht erst beim nächsten Standort-Update.
        Publishers.Merge(locationService.$heading, locationService.$lookDirection)
            .sink { [weak self] _ in
                self?.refreshManeuver()
            }
            .store(in: &cancellables)
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        // POIs und Barrieren sind für die ganze Altstadt und standortunabhängig
        // geladen – hier nur den Routenfortschritt aktualisieren.
        if let route = activeRoute {
            routeProgress = RouteService.progress(of: route, at: location)
            nextManeuver = RouteService.nextManeuver(of: route, at: location, heading: locationService.viewingDirection)
            lastManeuverRefresh = Date()
            considerReroute(from: location)
        }
    }

    /// Zeitpunkt der letzten Manöver-Neuberechnung (leichte Drosselung, weil
    /// die Blickrichtung mit ~20 Hz kommt).
    private var lastManeuverRefresh: Date?

    /// Berechnet nur die Abbiege-Anweisung neu (bei Blickrichtungsänderung).
    /// Gedrosselt auf ~4×/s und nur veröffentlicht, wenn sie sich ändert –
    /// so bleibt die Anzeige ruhig.
    private func refreshManeuver() {
        guard let route = activeRoute,
              let location = locationService.currentLocation else { return }
        let now = Date()
        if let last = lastManeuverRefresh, now.timeIntervalSince(last) < 0.25 { return }
        lastManeuverRefresh = now

        let maneuver = RouteService.nextManeuver(
            of: route,
            at: location,
            heading: locationService.viewingDirection
        )
        if maneuver != nextManeuver {
            nextManeuver = maneuver
        }
    }

    /// Prüft bei jedem Standort-Update, ob der User zu weit neben der Route
    /// liegt, und stösst – entprellt und mit Sperrzeit – eine automatische
    /// Neuberechnung an. So passt sich die (AR-)Route an, wenn jemand der
    /// vorgeschlagenen Strecke nicht folgt (Feldtest-Rückmeldung Tag 1).
    private func considerReroute(from location: CLLocation) {
        guard let route = activeRoute, let profile = navigationProfile else { return }

        // Am Ziel weder warnen noch umleiten.
        if routeProgress?.hasArrived == true {
            offRouteUpdates = 0
            isOffRoute = false
            return
        }

        let offBy = RouteService.distance(from: location.coordinate, to: route)
        guard offBy > offRouteThresholdM else {
            offRouteUpdates = 0
            isOffRoute = false
            return
        }

        offRouteUpdates += 1
        guard offRouteUpdates >= offRouteConfirmations else { return }

        // Bestätigt neben der Route: den Hinweis zeigen (auch offline, wenn
        // keine Neuberechnung möglich ist – dann bleibt die bisherige Route).
        isOffRoute = true

        // Neuberechnung nur online, nicht während einer laufenden Berechnung,
        // und höchstens einmal pro Sperrzeit.
        guard !isRerouting, !isCalculatingRoute, ConnectivityMonitor.shared.isOnline else { return }
        if let last = lastRerouteAt, Date().timeIntervalSince(last) < minRerouteInterval {
            return
        }

        lastRerouteAt = Date()
        Task { await reroute(from: location, profile: profile) }
    }

    /// Berechnet die Route vom aktuellen Standort zum unveränderten Ziel neu,
    /// unter Beibehaltung der für heute umgangenen Barrieren. Bei Misserfolg
    /// (Funkloch) bleibt die bestehende Route erhalten.
    private func reroute(from location: CLLocation, profile: UserProfile) async {
        guard let route = activeRoute else { return }
        let destination = route.destinationCoordinate
        let destinationName = route.destinationName

        isRerouting = true
        defer { isRerouting = false }

        let avoidCoordinates = barriers
            .filter { avoidedBarrierIds.contains($0.id) }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }

        do {
            let newRoute: ActiveRoute
            if avoidCoordinates.isEmpty {
                newRoute = try await RouteService.route(
                    from: location.coordinate,
                    to: destination,
                    destinationName: destinationName,
                    profile: profile
                )
            } else {
                newRoute = try await RouteService.wheelchairRoute(
                    from: location.coordinate,
                    to: destination,
                    destinationName: destinationName,
                    profile: profile,
                    avoiding: avoidCoordinates
                )
            }

            // Während der Neuberechnung gestoppt oder Ziel gewechselt? Verwerfen.
            guard let current = activeRoute,
                  current.destinationCoordinate.latitude == destination.latitude,
                  current.destinationCoordinate.longitude == destination.longitude
            else { return }

            activeRoute = newRoute
            // Jetzt startet die Route am aktuellen Standort → wieder auf Kurs.
            isOffRoute = false
            offRouteUpdates = 0
            if let latest = locationService.currentLocation {
                routeProgress = RouteService.progress(of: newRoute, at: latest)
                nextManeuver = RouteService.nextManeuver(of: newRoute, at: latest, heading: locationService.viewingDirection)
            }
        } catch {
            // Neuberechnung fehlgeschlagen – bestehende Route beibehalten.
        }
    }

    /// Lädt die Barrieren der ganzen Zürcher Altstadt (fixes Gebiet, unabhängig
    /// vom Standort – der Radius um das Altstadt-Zentrum deckt Kreis 1 ab).
    func loadBarriers() async {
        // Cache zuerst → sofortige Anzeige beim Start (schnelle Ladezeit),
        // dann Netz-Refresh im Hintergrund.
        if barriers.isEmpty,
           let cached = LocalDataStore.load([Barrier].self, named: "barriers") {
            barriers = cached
        }
        // Allererster Start ohne Netz und ohne Cache: gebündelter Seed, damit
        // die Karte garantiert Daten hat.
        if barriers.isEmpty {
            barriers = SeedData.barriers
        }
        isLoading = barriers.isEmpty
        loadError = nil
        defer { isLoading = false }

        do {
            let fresh = try await repository.fetchBarriers(
                near: AppConfig.altstadtCenter,
                radius: AppConfig.altstadtRadiusM
            )
            barriers = fresh
            LocalDataStore.save(fresh, named: "barriers")
        } catch {
            // Nur als Fehler zeigen, wenn gar keine (auch keine gecachten)
            // Daten vorliegen – sonst bleibt die App mit den letzten Daten
            // bedienbar (Funkloch in den Gassen).
            if barriers.isEmpty {
                loadError = error.localizedDescription
            }
        }
    }

    // MARK: - AR-Navigation

    /// Berechnet die rollstuhlgerechte Route zum POI (mit den Limits aus
    /// dem Profil) und startet die Navigation. Fällt auf die MapKit-
    /// Fussgängerroute zurück, wenn keine Rollstuhl-Route verfügbar ist.
    /// - Returns: `true`, wenn eine Route gefunden wurde.
    @discardableResult
    func startNavigation(to poi: POI, profile: UserProfile) async -> Bool {
        guard let start = locationService.currentLocation?.coordinate else {
            loadError = "Standort unbekannt – Navigation nicht möglich."
            return false
        }
        isCalculatingRoute = true
        defer { isCalculatingRoute = false }

        do {
            let route = try await RouteService.route(
                from: start,
                to: CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude),
                destinationName: poi.name,
                profile: profile
            )
            activeRoute = route
            navigationTarget = poi
            navigationProfile = profile
            offRouteUpdates = 0
            isOffRoute = false
            lastRerouteAt = nil
            routeProgress = RouteProgress(
                remainingDistanceM: route.totalDistanceM,
                remainingTimeS: route.expectedTravelTimeS
            )
            if let location = locationService.currentLocation {
                nextManeuver = RouteService.nextManeuver(of: route, at: location, heading: locationService.viewingDirection)
            }
            // Ziel für die "Letzte Ziele"-Liste auf dem Homescreen merken.
            RecentDestinationsStore.shared.record(
                name: poi.name,
                latitude: poi.latitude,
                longitude: poi.longitude
            )
            return true
        } catch {
            loadError = error.localizedDescription
            return false
        }
    }

    func stopNavigation() {
        activeRoute = nil
        navigationTarget = nil
        navigationProfile = nil
        routeProgress = nil
        nextManeuver = nil
        avoidedBarrierIds = []
        offRouteUpdates = 0
        isOffRoute = false
        lastRerouteAt = nil
    }

    /// Markiert die Barriere für heute als "nicht machbar" (Tagesform,
    /// z. B. Hitze) und berechnet die Route zum aktuellen Ziel neu, so dass
    /// sie diese – und alle zuvor markierten – Barrieren umgeht. Bewusst
    /// ohne Fussgänger-Fallback: der würde die Barriere nicht umgehen.
    /// - Returns: `true`, wenn eine Alternativroute gefunden wurde.
    @discardableResult
    func findAlternativeRoute(avoiding barrier: Barrier, profile: UserProfile) async -> Bool {
        guard let route = activeRoute else { return false }
        guard let start = locationService.currentLocation?.coordinate else {
            loadError = "Standort unbekannt – Alternativroute nicht möglich."
            return false
        }

        let previouslyAvoided = avoidedBarrierIds
        avoidedBarrierIds.insert(barrier.id)
        let avoidCoordinates = barriers
            .filter { avoidedBarrierIds.contains($0.id) }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }

        isCalculatingRoute = true
        defer { isCalculatingRoute = false }

        do {
            let newRoute = try await RouteService.wheelchairRoute(
                from: start,
                to: route.destinationCoordinate,
                destinationName: route.destinationName,
                profile: profile,
                avoiding: avoidCoordinates
            )
            activeRoute = newRoute
            routeProgress = RouteProgress(
                remainingDistanceM: newRoute.totalDistanceM,
                remainingTimeS: newRoute.expectedTravelTimeS
            )
            if let location = locationService.currentLocation {
                nextManeuver = RouteService.nextManeuver(of: newRoute, at: location, heading: locationService.viewingDirection)
            }
            return true
        } catch {
            avoidedBarrierIds = previouslyAvoided
            return false
        }
    }

    /// Setzt den aktiven Kategorie-Chip (nil = alle POIs der Altstadt) und
    /// beendet eine laufende Freitext-Suche. Rein client-seitig, kein RPC.
    func setCategory(_ label: String?) {
        searchResults = nil
        activeCategory = label
    }

    /// Kategorie-Chip getippt: filtert die Altstadt-POIs auf die Kategorie,
    /// nochmaliges Tippen deaktiviert und zeigt wieder alle POIs.
    func toggleCategory(_ category: String) {
        setCategory(activeCategory == category ? nil : category)
    }

    /// Freitext-Suche aus dem SearchSheet (RPC, matcht über Name UND
    /// Kategorie). Ergebnis wird zurückgegeben UND als Karten-Marker
    /// übernommen. Gesucht wird immer in der ganzen Altstadt.
    func searchPOIs(query: String) async -> [POI] {
        recordRecentSearch(query)
        do {
            let results = try await poiRepository.fetchPOIs(
                near: AppConfig.altstadtCenter,
                radius: AppConfig.altstadtRadiusM,
                search: POICategory.searchTerm(forChip: query)
            )
            searchResults = results
            activeCategory = nil
            return results
        } catch {
            loadError = error.localizedDescription
            return []
        }
    }

    /// Lädt einmalig alle POIs der ganzen Zürcher Altstadt – die Basisliste
    /// für Karte, AR und die client-seitigen Kategorie-Filter.
    private func loadPOIs() async {
        // Cache zuerst → sofortige Anzeige beim Start, dann Netz-Refresh.
        if altstadtPOIs.isEmpty,
           let cached = LocalDataStore.load([POI].self, named: "pois") {
            altstadtPOIs = cached
        }
        // Allererster Start ohne Netz und ohne Cache: gebündelter Seed.
        if altstadtPOIs.isEmpty {
            altstadtPOIs = SeedData.pois
        }
        do {
            let fresh = try await poiRepository.fetchPOIs(
                near: AppConfig.altstadtCenter,
                radius: AppConfig.altstadtRadiusM
            )
            altstadtPOIs = fresh
            LocalDataStore.save(fresh, named: "pois")
        } catch {
            // Nur melden, wenn gar keine (auch keine gecachten) POIs da sind.
            if altstadtPOIs.isEmpty {
                loadError = error.localizedDescription
            }
        }
    }

    // MARK: - Letzte Suchen (max. 5, UserDefaults)

    private func loadRecentSearches() {
        recentSearches = UserDefaults.standard.stringArray(forKey: recentSearchesKey) ?? []
    }

    private func recordRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var searches = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        searches.insert(trimmed, at: 0)
        recentSearches = Array(searches.prefix(5))
        UserDefaults.standard.set(recentSearches, forKey: recentSearchesKey)
    }
}