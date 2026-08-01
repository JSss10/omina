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
    /// Bisher auf der aktiven Route zurückgelegte Weglänge (Meter ab Start).
    /// Hält die Projektion des Standorts auf die Route vorwärtsgerichtet:
    /// Läuft die Route dicht an sich selbst vorbei (Umweg über die nächste
    /// Brücke, Parallelgassen der Altstadt), würde sonst der falsche Ast als
    /// "nächstes Segment" gewinnen – Restweg, Kartendrehung und Abbiege-Ansage
    /// ("Bitte umdrehen") kippen dann schlagartig. nil = noch kein Bezugspunkt.
    @Published private(set) var routeAnchorAlongM: CLLocationDistance?

    /// Profil der aktiven Navigation – für die automatische Neuberechnung
    /// (Rollstuhl-Limits) gemerkt, solange eine Route läuft.
    private var navigationProfile: UserProfile?
    /// Aufeinanderfolgende Standort-Updates, in denen der User zu weit neben
    /// der Route lag (Entprellung gegen GPS-Ausreisser).
    private var offRouteUpdates = 0
    /// Aufeinanderfolgende Updates, in denen der Fusspunkt klar neben dem
    /// erwarteten Routenabschnitt lag – danach wird der Anker gelöst.
    private var anchorMissUpdates = 0
    /// Zeitpunkt der letzten automatischen Neuberechnung (Sperrzeit dazwischen).
    private var lastRerouteAt: Date?

    /// Seitlicher Abstand zur Route, ab dem als "nicht auf der Route" gilt.
    private let offRouteThresholdM: CLLocationDistance = 25
    /// So viele Updates in Folge über der Schwelle lösen die Neuberechnung aus.
    private let offRouteConfirmations = 2
    /// Vielfaches der Schwelle, ab dem ein einzelnes (verlässliches) Update
    /// genügt: Wer eine Gasse weiter fährt, ist eindeutig auf einem eigenen Weg –
    /// darauf soll die App sofort reagieren statt erst nach mehreren Updates.
    private let offRouteImmediateFactor: CLLocationDistance = 2
    /// Mindestabstand zwischen zwei automatischen Neuberechnungen.
    private let minRerouteInterval: TimeInterval = 8
    /// Genauigkeit, die ein Fix mindestens haben muss, damit er eine
    /// automatische Neuberechnung auslösen darf. Ohne diese Schranke berechnet
    /// ein einzelner GPS-Ausreisser die ganze Route neu – vom falschen Ort aus.
    private let maxRerouteAccuracyM: CLLocationAccuracy = 25
    /// Bis zu diesem seitlichen Abstand gilt der Fusspunkt als "auf der Route"
    /// und schiebt den Fortschritts-Anker weiter.
    private let routeAnchorMaxOffsetM: CLLocationDistance = 30
    /// So viele Updates klar daneben lösen den Anker wieder (man ist wirklich
    /// woanders, nicht nur kurz verrauscht).
    private let routeAnchorMissLimit = 3

    private let locationService: LocationService
    private let repository: BarrierRepository
    private let poiRepository: POIRepository
    private let recentSearchesKey = "armikronav.recentSearches"

    private var cancellables = Set<AnyCancellable>()
    private var hasStarted = false

    var filteredBarriers: [Barrier] {
        barriers.filter { filterState.enabledTypes.contains($0.type) }
    }

    /// Halbe Korridor-Breite bei rollstuhlgerechter Route (OpenRouteService).
    /// Deren Geometrie folgt den Gehwegen selbst, deshalb bewusst eng (6 m):
    /// In der Altstadt sind Häuserblöcke nur ~20–30 m tief, ein breiter
    /// Korridor würde die Barrieren der Nachbargasse mitzählen.
    private let wheelchairCorridorM: CLLocationDistance = 6
    /// Halbe Korridor-Breite bei der Fussgänger-Fallback-Route (MapKit).
    /// Deren Geometrie liegt auf der Strassenachse – im Rollstuhl fährt man
    /// aber auf dem Trottoir links oder rechts davon, und genau dort liegen
    /// die Bordsteine, Steigungen und Oberflächen. Mit 6 m fielen sie aus dem
    /// Korridor und die Route sähe barrierefrei aus, obwohl sie es nicht ist.
    /// 12 m deckt Fahrbahn plus beide Trottoirs ab und bleibt unter der Tiefe
    /// eines Altstadt-Häuserblocks.
    private let walkingCorridorM: CLLocationDistance = 12

    /// Halbe Korridor-Breite für die aktive Route – abhängig davon, ob die
    /// Geometrie den Gehwegen (Rollstuhl-Route) oder der Strassenachse
    /// (Fussgänger-Fallback) folgt.
    private func corridorM(for kind: RouteKind) -> CLLocationDistance {
        switch kind {
        case .wheelchair, .wheelchairRelaxed: return wheelchairCorridorM
        case .walkingFallback:                return walkingCorridorM
        }
    }

    /// Zählfunktion für die Routenauswahl: Wie viele Stellen entlang einer
    /// Route sind für dieses Profil kritisch (shouldWarn)?
    ///
    /// Bewusst als geschlossene Funktion über eine Momentaufnahme der
    /// Barrieren-Koordinaten – so kann RouteService die Varianten vergleichen,
    /// ohne die Barrierendaten oder das ViewModel zu kennen. Dieselben
    /// Korridor-Breiten wie in der Anzeige, damit die Auswahl mit dem
    /// übereinstimmt, was das Panel danach ausweist.
    private func criticalBarrierCounter(
        for profile: UserProfile
    ) -> (ActiveRoute) -> Int {
        let criticalCoordinates = filteredBarriers
            .filter { shouldWarn(barrier: $0, profile: profile) }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let wheelchairCorridor = wheelchairCorridorM
        let walkingCorridor = walkingCorridorM

        return { route in
            let corridor = route.kind.usesOSMWheelchairRouting
                ? wheelchairCorridor
                : walkingCorridor
            return criticalCoordinates.filter {
                RouteService.distance(from: $0, to: route) <= corridor
            }.count
        }
    }

    /// Barrieren, die auf der Karte/AR angezeigt werden:
    /// – Barrieren per Toggle ausgeblendet → keine
    /// – aktive Route → nur Barrieren im Korridor direkt entlang der Route,
    ///   co-lokalisierte zu EINER Stelle zusammengefasst (siehe unten)
    /// – sonst → nur profilrelevante Barrieren im engen Umkreis des Standorts
    ///   (nearbyDisplayRadiusM), co-lokalisierte zusammengefasst
    ///
    /// Unabhängig davon laufen die Annäherungswarnungen (Banner und System-
    /// Mitteilung) über `filteredBarriers`, also über ALLE profilrelevanten
    /// Barrieren im Warnradius um den tatsächlichen Standort – auch über
    /// solche, die hier nicht als Marker erscheinen.
    var displayedBarriers: [Barrier] {
        guard barriersVisible else { return [] }
        if let route = activeRoute {
            let corridorM = corridorM(for: route.kind)
            let onRoute = filteredBarriers.filter { barrier in
                RouteService.distance(
                    from: CLLocationCoordinate2D(
                        latitude: barrier.latitude,
                        longitude: barrier.longitude
                    ),
                    to: route
                ) <= corridorM
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

    /// Index des Schritts, den der User gerade zurücklegt (für die Hervorhebung
    /// in der Turn-by-turn-Liste). Schritte davor gelten als erledigt, danach
    /// als bevorstehend. nil, wenn keine Route mit Schritten aktiv ist; ohne
    /// Standort-Fix der erste Schritt.
    var currentStepIndex: Int? {
        guard let route = activeRoute, !route.steps.isEmpty else { return nil }
        guard let location = locationService.currentLocation else { return 0 }
        let userAlongM = RouteService.distanceAlongRoute(to: location.coordinate, on: route)
        var cumulativeM = 0.0
        for (index, step) in route.steps.enumerated() {
            cumulativeM += step.distanceM
            if userAlongM < cumulativeM { return index }
        }
        return route.steps.count - 1
    }

    /// POIs nach Luftlinien-Distanz zum aktuellen Standort sortiert – die
    /// Datenbasis der "In der Nähe"-Liste in der Suche. Ohne Standort-Fix nach
    /// der importierten Distanz sortiert.
    func nearbyPOIs(limit: Int = 12) -> [POI] {
        guard let user = locationService.currentLocation else {
            return Array(altstadtPOIs.sorted { $0.distanceM < $1.distanceM }.prefix(limit))
        }
        return altstadtPOIs
            .sorted {
                user.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                    < user.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Luftlinien-Distanz eines POI zum aktuellen Standort als String; ohne
    /// Standort-Fix die importierte Distanz (relativ zum Altstadt-Zentrum).
    func userDistanceText(to poi: POI) -> String {
        if let user = locationService.currentLocation {
            let meters = user.distance(from: CLLocation(latitude: poi.latitude, longitude: poi.longitude))
            return DistanceFormatter.string(fromMeters: meters)
        }
        return DistanceFormatter.string(fromMeters: poi.distanceM)
    }

    /// Findet den geladenen Altstadt-POI zu einem Namen (case-insensitiv) –
    /// löst einen Eintrag der "Letzte Orte"-Liste zurück auf einen echten POI
    /// auf, damit die Auswahl im gewohnten POI-Detail landet.
    func poi(named name: String) -> POI? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return altstadtPOIs.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    /// POIs, die auf der Karte/AR angezeigt werden:
    /// – aktive Navigation → nur noch das Ziel (auch bei ausgeblendeten POIs,
    ///   damit das Navigationsziel immer sichtbar bleibt)
    /// – POIs per Toggle ausgeblendet → keine
    /// – aktive Freitext-Suche → deren Treffer (bewusst NICHT auf den Umkreis
    ///   beschränkt: eine gezielte Suche soll auch entfernte Treffer zeigen)
    /// – aktiver Kategorie-Chip → die `nearestCategoryLimit` nächstgelegenen
    ///   Orte dieser Kategorie
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
            return poisForCategory(activeCategory, limit: AppConfig.nearestCategoryLimit)
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

    /// Altstadt-POIs eines Kategorie-Chips (exaktes Key-Matching), nach
    /// Luftlinie zum aktuellen Standort sortiert – die Datenbasis der
    /// Ergebnisliste im SearchSheet, der Karten-Marker und der AR-Karten.
    /// Ohne Standort-Fix zählt die importierte Distanz. `limit` begrenzt auf
    /// die nächstgelegenen Treffer (nil = alle, z. B. für die Trefferzahl).
    func poisForCategory(_ label: String, limit: Int? = nil) -> [POI] {
        guard let chip = POICategory.chip(forLabel: label) else { return [] }
        let matching = altstadtPOIs.filter { chip.matches(category: $0.category) }
        let sorted: [POI]
        if let user = locationService.currentLocation {
            sorted = matching.sorted {
                user.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                    < user.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
            }
        } else {
            sorted = matching.sorted { $0.distanceM < $1.distanceM }
        }
        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
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
            updateRouteAnchor(for: route, at: location)
            routeProgress = RouteService.progress(
                of: route,
                at: location,
                alongAnchorM: routeAnchorAlongM
            )
            nextManeuver = RouteService.nextManeuver(
                of: route,
                at: location,
                heading: locationService.viewingDirection,
                alongAnchorM: routeAnchorAlongM
            )
            lastManeuverRefresh = Date()
            considerReroute(from: location)
        }
    }

    /// Führt den Fortschritts-Anker entlang der Route nach. Solange der
    /// Fusspunkt nah genug an der Route liegt, rückt der Anker mit; liegt er
    /// mehrfach klar daneben, wird er gelöst, damit die Verortung wieder frei
    /// das nächstgelegene Segment wählen kann (z. B. nach einer Abkürzung).
    private func updateRouteAnchor(for route: ActiveRoute, at location: CLLocation) {
        // Verrauschte Fixes den Anker nicht verschieben lassen – er soll den
        // tatsächlichen Fortschritt abbilden, nicht das GPS-Rauschen.
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= LocationService.usableAccuracyM else { return }

        guard let fix = RouteService.locate(
            on: route,
            at: location,
            alongAnchorM: routeAnchorAlongM
        ) else {
            routeAnchorAlongM = nil
            anchorMissUpdates = 0
            return
        }

        if fix.offsetM <= routeAnchorMaxOffsetM {
            routeAnchorAlongM = fix.alongM
            anchorMissUpdates = 0
            return
        }

        anchorMissUpdates += 1
        if anchorMissUpdates >= routeAnchorMissLimit {
            routeAnchorAlongM = nil
            anchorMissUpdates = 0
        }
    }

    /// Standortkoordinate für die Karten-Marker: während der Navigation auf die
    /// Route eingerastet, solange man nah genug an ihr ist – so springt der
    /// Punkt nicht neben der Linie herum (GPS-Rauschen in den engen Gassen).
    /// Ohne aktive Route die Rohposition.
    func snappedCoordinate(
        for location: CLLocation,
        maxOffsetM: CLLocationDistance = 12
    ) -> CLLocationCoordinate2D {
        guard let route = activeRoute else { return location.coordinate }
        let snap = RouteService.snappedLocation(
            on: route,
            at: location,
            alongAnchorM: routeAnchorAlongM
        )
        return snap.offsetM <= maxOffsetM ? snap.coordinate : location.coordinate
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
            heading: locationService.viewingDirection,
            alongAnchorM: routeAnchorAlongM
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

        // Nur verlässliche Fixes dürfen eine Neuberechnung auslösen. In den
        // Altstadtgassen springt der Standort sonst regelmässig auf die andere
        // Limmatseite – die Route würde von dort aus neu berechnet und führte
        // kilometerweit über die nächste Brücke, obwohl das Ziel nebenan liegt.
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maxRerouteAccuracyM else {
            offRouteUpdates = 0
            return
        }

        // Schwelle mit der gemeldeten Genauigkeit skalieren: Ein Fix mit 20 m
        // Streuung darf nicht schon als "abgekommen" zählen.
        let threshold = max(offRouteThresholdM, location.horizontalAccuracy * 2)
        let offBy = RouteService.distance(from: location.coordinate, to: route)
        guard offBy > threshold else {
            offRouteUpdates = 0
            isOffRoute = false
            return
        }

        offRouteUpdates += 1
        // Klar daneben (mehrfache Schwelle) → sofort reagieren, sonst erst nach
        // mehreren Updates in Folge (Entprellung gegen GPS-Ausreisser).
        let isUnmistakable = offBy > threshold * offRouteImmediateFactor
        guard isUnmistakable || offRouteUpdates >= offRouteConfirmations else { return }

        // Bestätigt neben der Route: den Hinweis zeigen (auch offline, wenn
        // keine Neuberechnung möglich ist – dann bleibt die bisherige Route).
        isOffRoute = true
        // Wirklich abgekommen: Der Fortschritts-Anker gilt nicht mehr, die
        // Verortung darf wieder frei das nächstgelegene Segment wählen.
        routeAnchorAlongM = nil
        anchorMissUpdates = 0

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
                    profile: profile,
                    criticalBarriers: criticalBarrierCounter(for: profile)
                )
            } else {
                newRoute = try await RouteService.wheelchairRoute(
                    avoiding: avoidCoordinates,
                    from: location.coordinate,
                    to: destination,
                    destinationName: destinationName,
                    profile: profile
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
            routeAnchorAlongM = 0
            anchorMissUpdates = 0
            if let latest = locationService.currentLocation {
                routeProgress = RouteService.progress(of: newRoute, at: latest, alongAnchorM: 0)
                nextManeuver = RouteService.nextManeuver(
                    of: newRoute,
                    at: latest,
                    heading: locationService.viewingDirection,
                    alongAnchorM: 0
                )
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
        guard let startLocation = locationService.currentLocation else {
            loadError = "Standort unbekannt – Navigation nicht möglich."
            return false
        }
        // Mit einem stark verrauschten Fix würde die Route am falschen Ort
        // beginnen (in der Altstadt schnell auf der anderen Limmatseite) und
        // einen absurden Umweg vorschlagen. Dann lieber kurz warten.
        guard locationService.hasReliableFix else {
            loadError = "Standort noch ungenau – bitte kurz warten und erneut versuchen."
            return false
        }
        let start = startLocation.coordinate
        // Ein früherer Hinweis (z. B. "Standort noch ungenau") ist mit dem
        // neuen Versuch überholt.
        loadError = nil
        isCalculatingRoute = true
        defer { isCalculatingRoute = false }

        do {
            let route = try await RouteService.route(
                from: start,
                to: CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude),
                destinationName: poi.name,
                profile: profile,
                criticalBarriers: criticalBarrierCounter(for: profile)
            )
            activeRoute = route
            navigationTarget = poi
            navigationProfile = profile
            // Dichtere Standort-Updates während der Navigation – Fortschritt,
            // Kartendrehung und das Erkennen eines eigenen Wegs reagieren so
            // zeitnah.
            locationService.setNavigationActive(true)
            offRouteUpdates = 0
            isOffRoute = false
            lastRerouteAt = nil
            routeAnchorAlongM = 0
            anchorMissUpdates = 0
            // Umgangene Barrieren gelten pro Navigation – sonst würde die
            // nächste Route ohne erkennbaren Grund um alte Sperrflächen
            // herumgeführt (und dadurch unnötig lang).
            avoidedBarrierIds = []
            routeProgress = RouteProgress(
                remainingDistanceM: route.totalDistanceM,
                remainingTimeS: route.expectedTravelTimeS
            )
            if let location = locationService.currentLocation {
                nextManeuver = RouteService.nextManeuver(
                    of: route,
                    at: location,
                    heading: locationService.viewingDirection,
                    alongAnchorM: 0
                )
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
        locationService.setNavigationActive(false)
        activeRoute = nil
        navigationTarget = nil
        navigationProfile = nil
        routeProgress = nil
        nextManeuver = nil
        avoidedBarrierIds = []
        offRouteUpdates = 0
        isOffRoute = false
        lastRerouteAt = nil
        routeAnchorAlongM = nil
        anchorMissUpdates = 0
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
                avoiding: avoidCoordinates,
                from: start,
                to: route.destinationCoordinate,
                destinationName: route.destinationName,
                profile: profile
            )
            activeRoute = newRoute
            routeAnchorAlongM = 0
            anchorMissUpdates = 0
            routeProgress = RouteProgress(
                remainingDistanceM: newRoute.totalDistanceM,
                remainingTimeS: newRoute.expectedTravelTimeS
            )
            if let location = locationService.currentLocation {
                nextManeuver = RouteService.nextManeuver(
                    of: newRoute,
                    at: location,
                    heading: locationService.viewingDirection,
                    alongAnchorM: 0
                )
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