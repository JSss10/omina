// MapViewModel.swift
// Omina
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
    @Published private(set) var barriers: [Barrier] = [] { didSet { barrierDataRevision &+= 1 } }
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?
    @Published private(set) var filterState: BarrierFilterState = .default {
        didSet { filteredBarriersRevision &+= 1 }
    }

    // Sichtbarkeits-Toggles (Karte & AR): blenden Barrieren- bzw. POI-Marker
    // komplett aus. Rein visuell – Annäherungswarnungen laufen weiterhin über
    // filteredBarriers, damit ausgeblendete Barrieren trotzdem warnen.
    @Published var barriersVisible = true
    @Published var poisVisible = true

    /// Kategorie, die vom Homescreen aus vorgewählt wurde. Die Karte öffnet
    /// damit die Suche und setzt den Wert danach zurück.
    @Published var pendingCategory: String?

    /// Wie viele Filter gerade greifen – ausgeblendete Orte, ausgeblendete
    /// Barrieren und jeder abgewählte Barrieretyp zählen einzeln. Steht als
    /// Plakette an der Filter-Schaltfläche (Entwurf).
    var activeFilterCount: Int {
        var count = 0
        if !poisVisible { count += 1 }
        if !barriersVisible { count += 1 }
        count += BarrierType.allCases.count - filterState.enabledTypes.count
        return count
    }

    /// Zählt jede Änderung an der Barrieren-Grundmenge oder am Filter mit –
    /// also genau die Fälle, in denen sich `filteredBarriers` ändern kann.
    /// Views beobachten diesen Zähler statt die Liste selbst zu vergleichen
    /// (`onChange(of: filteredBarriers.map(\.id))` baute je Bildaufbau ein
    /// neues UUID-Array auf, nur um festzustellen, dass sich nichts geändert hat).
    @Published private(set) var filteredBarriersRevision = 0

    /// Interne Zähler für den Zwischenspeicher der abgeleiteten Listen.
    private var barrierDataRevision = 0 { didSet { filteredBarriersRevision &+= 1 } }
    private var poiDataRevision = 0

    // POIs (Wireframe 2.1/2.1a): standardmässig alle POIs der Altstadt
    // (einmalig geladen). Kategorie-Chips filtern diese Liste client-seitig
    // über die exakten ginto-Kategorie-Keys; nur die Freitext-Suche läuft
    // über die RPC.
    @Published private(set) var altstadtPOIs: [POI] = [] { didSet { poiDataRevision &+= 1 } }
    /// Ergebnis der letzten Freitext-Suche (nil = keine aktive Suche).
    @Published private(set) var searchResults: [POI]? { didSet { poiDataRevision &+= 1 } }
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
    /// Letzter gescheiterter Routenstart – trägt den Zustands-Screen
    /// "Keine Route gefunden" samt Ziel für "Erneut versuchen".
    @Published private(set) var routeFailure: RouteFailure?
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
    private let recentSearchesKey = "omina.recentSearches"

    private var cancellables = Set<AnyCancellable>()
    private var hasStarted = false

    // MARK: - Zwischenspeicher der abgeleiteten Listen
    //
    // `filteredBarriers`, `displayedBarriers`, `displayedPOIs` und
    // `routeBarrierEntries` werden aus SwiftUI-`body` gelesen – auf der Karte
    // mehrfach je Bildaufbau, und die Blickrichtung des Geräts stösst laufend
    // neue Durchläufe an. Ohne Zwischenspeicher würde dabei jedes Mal jede
    // Barriere erneut gegen die ganze Routen-Polyline projiziert
    // (Barrieren × Wegpunkte), was den Hauptthread auslastet und das Gerät im
    // AR-Betrieb thermisch drosselt.
    //
    // Deshalb wird das Ergebnis unter einem Schlüssel gemerkt, der genau die
    // Eingaben abbildet, aus denen es entsteht. Ändert sich keine davon, ist
    // der Zugriff O(1); ändert sich eine, wird neu gerechnet. Die Listen
    // bleiben damit exakt dieselben wie zuvor – nur eben nicht mehr je Bild.

    /// Die Eingaben, aus denen die abgeleiteten Listen entstehen.
    private struct DerivedInputs: Equatable {
        let barrierDataRevision: Int
        let poiDataRevision: Int
        let filterState: BarrierFilterState
        let barriersVisible: Bool
        let poisVisible: Bool
        let routeID: UUID?
        let navigationTargetID: UUID?
        let activeCategory: String?
        /// Standort, auf ~1 m gerastert – feiner ändert die Auswahl nichts.
        let locationGrid: LocationGrid?

        struct LocationGrid: Equatable {
            let latitude: Int
            let longitude: Int

            init(_ coordinate: CLLocationCoordinate2D) {
                latitude = Int((coordinate.latitude * 100_000).rounded())
                longitude = Int((coordinate.longitude * 100_000).rounded())
            }
        }
    }

    private var derivedInputs: DerivedInputs {
        DerivedInputs(
            barrierDataRevision: barrierDataRevision,
            poiDataRevision: poiDataRevision,
            filterState: filterState,
            barriersVisible: barriersVisible,
            poisVisible: poisVisible,
            routeID: activeRoute?.id,
            navigationTargetID: navigationTarget?.id,
            activeCategory: activeCategory,
            locationGrid: locationService.currentLocation
                .map { DerivedInputs.LocationGrid($0.coordinate) }
        )
    }

    private var derivedCacheInputs: DerivedInputs?
    private var cachedFilteredBarriers: [Barrier]?
    private var cachedDisplayedBarriers: [Barrier]?
    private var cachedDisplayedPOIs: [POI]?
    private var cachedRouteBarrierEntries: [RouteBarrierEntry]?

    /// Verwirft den Zwischenspeicher, sobald sich eine der Eingaben geändert hat.
    private func refreshDerivedCacheIfNeeded() {
        let inputs = derivedInputs
        guard inputs != derivedCacheInputs else { return }
        derivedCacheInputs = inputs
        cachedFilteredBarriers = nil
        cachedDisplayedBarriers = nil
        cachedDisplayedPOIs = nil
        cachedRouteBarrierEntries = nil
    }

    /// Barrieren, die der aktive Filter durchlässt. Grundlage der
    /// Annäherungswarnungen – bewusst unabhängig davon, was auf der Karte
    /// sichtbar ist (siehe `displayedBarriers`).
    var filteredBarriers: [Barrier] {
        refreshDerivedCacheIfNeeded()
        if let cachedFilteredBarriers { return cachedFilteredBarriers }
        let value = barriers.filter { filterState.enabledTypes.contains($0.type) }
        cachedFilteredBarriers = value
        return value
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
        case .wheelchair: return wheelchairCorridorM
        case .walking:    return walkingCorridorM
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
        refreshDerivedCacheIfNeeded()
        if let cachedDisplayedBarriers { return cachedDisplayedBarriers }
        let value = computeDisplayedBarriers()
        cachedDisplayedBarriers = value
        return value
    }

    private func computeDisplayedBarriers() -> [Barrier] {
        guard barriersVisible else { return [] }
        if let route = activeRoute {
            let corridorM = corridorM(for: route.kind)
            // Die Route einmal in das lokale Meter-System umrechnen, statt je
            // Barriere erneut (siehe RouteService.path).
            let path = RouteService.path(of: route)
            let onRoute = filteredBarriers.filter { barrier in
                RouteService.offsetAndAlong(of: barrier.coordinate, on: path).offsetM <= corridorM
            }
            return collapseColocated(onRoute)
        }
        // Ohne Route nur die Barrieren im engen Umkreis des aktuellen
        // Standorts anzeigen (Überlastung vermeiden); passt sich beim
        // Weiterfahren an.
        return collapseColocated(nearCurrentLocation(filteredBarriers, at: \.coordinate))
    }

    /// Filtert Elemente auf den Anzeige-Umkreis (nearbyDisplayRadiusM) um den
    /// aktuellen Standort. Bewusst eng, damit in der dichten Altstadt nur die
    /// unmittelbare Umgebung sichtbar ist (Feldtest-Rückmeldung Tag 1). Ohne
    /// Standort-Fix (kurz nach dem Start) werden übergangsweise alle Elemente
    /// gezeigt. `coordinate` liefert die Position je Element.
    ///
    /// Gerechnet wird in quadrierten Metern der Flach-Erde-Näherung: Auf 50 m
    /// ist sie millimetergenau, spart aber je Element ein `CLLocation`-Objekt
    /// und eine Wurzel – bei mehreren hundert Elementen je Auswertung spürbar.
    private func nearCurrentLocation<Element>(
        _ elements: [Element],
        at coordinate: (Element) -> CLLocationCoordinate2D
    ) -> [Element] {
        guard let userLocation = locationService.currentLocation else { return elements }
        let origin = userLocation.coordinate
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(origin.latitude * .pi / 180)
        let radiusSquared = AppConfig.nearbyDisplayRadiusM * AppConfig.nearbyDisplayRadiusM

        return elements.filter { element in
            let position = coordinate(element)
            let north = (position.latitude - origin.latitude) * metersPerDegreeLatitude
            let east = (position.longitude - origin.longitude) * metersPerDegreeLongitude
            return north * north + east * east <= radiusSquared
        }
    }

    /// Raster, auf das `collapseColocated` Koordinaten legt. Ganzzahlig statt
    /// als formatierter String: `String(format:)` ist für einen reinen
    /// Wörterbuch-Schlüssel unverhältnismässig teuer (Locale-Behandlung und
    /// eine Zeichenkette je Barriere), das Ergebnis ist dasselbe.
    private struct ColocationKey: Hashable {
        let latitude: Int
        let longitude: Int

        /// 6 Nachkommastellen ≈ 0,11 m: fasst nur wirklich deckungsgleiche
        /// Punkte zusammen, keine benachbarten Barrieren.
        init(_ barrier: Barrier) {
            latitude = Int((barrier.latitude * 1_000_000).rounded())
            longitude = Int((barrier.longitude * 1_000_000).rounded())
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
        var representatives: [ColocationKey: Barrier] = [:]
        representatives.reserveCapacity(barriers.count)
        for barrier in barriers {
            let key = ColocationKey(barrier)
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
        refreshDerivedCacheIfNeeded()
        if let cachedRouteBarrierEntries { return cachedRouteBarrierEntries }
        let value = computeRouteBarrierEntries()
        cachedRouteBarrierEntries = value
        return value
    }

    private func computeRouteBarrierEntries() -> [RouteBarrierEntry] {
        guard let route = activeRoute else { return [] }
        // Wie in computeDisplayedBarriers: Route einmal umrechnen, dann alle
        // Barrieren dagegen verorten.
        let path = RouteService.path(of: route)
        let alongUser = locationService.currentLocation.map {
            RouteService.offsetAndAlong(of: $0.coordinate, on: path).alongM
        }
        return displayedBarriers
            .map { barrier in
                let along = RouteService.offsetAndAlong(of: barrier.coordinate, on: path).alongM
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
        Array(sortedByUserDistance(altstadtPOIs).prefix(limit))
    }

    /// Sortiert POIs nach Luftlinie zum aktuellen Standort; ohne Standort-Fix
    /// nach der importierten Distanz.
    ///
    /// Die Distanz wird EINMAL je POI berechnet und dann sortiert. Zuvor stand
    /// sie im Vergleicher – der läuft n·log(n)-mal und legte dabei jedes Mal
    /// zwei `CLLocation`-Objekte an; bei mehreren hundert Orten waren das
    /// Tausende überflüssiger Objekte je Aufruf.
    private func sortedByUserDistance(_ pois: [POI]) -> [POI] {
        guard let user = locationService.currentLocation else {
            return pois.sorted { $0.distanceM < $1.distanceM }
        }
        return pois
            .map { (poi: $0, distanceM: user.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
            .sorted { $0.distanceM < $1.distanceM }
            .map(\.poi)
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
        refreshDerivedCacheIfNeeded()
        if let cachedDisplayedPOIs { return cachedDisplayedPOIs }
        let value = computeDisplayedPOIs()
        cachedDisplayedPOIs = value
        return value
    }

    private func computeDisplayedPOIs() -> [POI] {
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
        // POIs im Anzeige-Umkreis (nearbyDisplayRadiusM) – dieselbe enge
        // Begrenzung wie bei den Barrieren, damit Karte und AR-Modus nur die
        // unmittelbare Umgebung zeigen.
        return nearCurrentLocation(altstadtPOIs, at: \.coordinate)
    }

    /// Altstadt-POIs eines Kategorie-Chips (exaktes Key-Matching), nach
    /// Luftlinie zum aktuellen Standort sortiert – die Datenbasis der
    /// Ergebnisliste im SearchSheet, der Karten-Marker und der AR-Karten.
    /// Ohne Standort-Fix zählt die importierte Distanz. `limit` begrenzt auf
    /// die nächstgelegenen Treffer (nil = alle, z. B. für die Trefferzahl).
    func poisForCategory(_ label: String, limit: Int? = nil) -> [POI] {
        guard let chip = POICategory.chip(forLabel: label) else { return [] }
        let sorted = sortedByUserDistance(
            altstadtPOIs.filter { chip.matches(category: $0.category) }
        )
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
            .map(\.coordinate)

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

    /// Gescheiterter Routenstart: Grund für den Zustands-Screen plus Ziel und
    /// Profil, damit "Erneut versuchen" denselben Versuch wiederholen kann.
    struct RouteFailure: Identifiable {
        let id = UUID()
        let reason: String
        let target: POI
        let profile: UserProfile
    }

    /// Berechnet die rollstuhlgerechte Route zum POI (mit den Limits aus
    /// dem Profil) und startet die Navigation. Fällt auf die MapKit-
    /// Fussgängerroute zurück, wenn keine Rollstuhl-Route verfügbar ist.
    /// - Returns: `true`, wenn eine Route gefunden wurde.
    @discardableResult
    func startNavigation(to poi: POI, profile: UserProfile) async -> Bool {
        // Ein früherer Fehlversuch ist mit dem neuen Versuch überholt.
        routeFailure = nil

        guard let startLocation = locationService.currentLocation else {
            return failRoute(
                "Dein Standort ist unbekannt – ohne Startpunkt lässt sich keine Route berechnen.",
                to: poi,
                profile: profile
            )
        }
        // Mit einem stark verrauschten Fix würde die Route am falschen Ort
        // beginnen (in der Altstadt schnell auf der anderen Limmatseite) und
        // einen absurden Umweg vorschlagen. Dann lieber kurz warten.
        guard locationService.hasReliableFix else {
            return failRoute(
                "Dein Standort ist noch ungenau. Warte einen Moment und versuche es dann erneut.",
                to: poi,
                profile: profile
            )
        }
        let start = startLocation.coordinate
        loadError = nil
        isCalculatingRoute = true
        defer { isCalculatingRoute = false }

        do {
            let route = try await RouteService.route(
                from: start,
                to: CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude),
                destinationName: poi.name,
                profile: profile
            )
            activate(route: route, to: poi, profile: profile)
            return true
        } catch {
            return failRoute(error.localizedDescription, to: poi, profile: profile)
        }
    }

    /// Übernimmt eine fertig berechnete Route als aktive Navigation. Gemeinsam
    /// genutzt von `startNavigation(to:profile:)` und der Variantenauswahl im
    /// Routen-Sheet, damit beide Wege denselben Startzustand herstellen.
    private func activate(route: ActiveRoute, to poi: POI, profile: UserProfile) {
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
            longitude: poi.longitude,
            imageURL: poi.images.first?.url
        )
    }

    /// Merkt den gescheiterten Versuch für den Zustands-Screen. Gibt immer
    /// `false` zurück, damit die Aufrufer direkt `return failRoute(…)` können.
    @discardableResult
    private func failRoute(_ reason: String, to poi: POI, profile: UserProfile) -> Bool {
        routeFailure = RouteFailure(reason: reason, target: poi, profile: profile)
        return false
    }

    /// "Erneut versuchen" aus dem Zustands-Screen: gleicher Zielort, gleiches
    /// Profil. Schlägt es wieder fehl, steht der Screen mit neuem Grund da.
    @discardableResult
    func retryFailedRoute() async -> Bool {
        guard let failure = routeFailure else { return false }
        return await startNavigation(to: failure.target, profile: failure.profile)
    }

    /// Schliesst den Zustands-Screen "Keine Route gefunden".
    func clearRouteFailure() {
        routeFailure = nil
    }

    // MARK: - Routen-Sheet: Varianten zur Auswahl

    /// Eine wählbare Wegvariante zum Ziel, samt der Barrieren, die im Korridor
    /// dieser Geometrie liegen – der Unterschied zwischen zwei Varianten liegt
    /// für Rollstuhlnutzende genau dort, nicht in der Minutenzahl.
    struct RouteOption: Identifiable {
        let route: ActiveRoute
        /// Barrieren im Korridor dieser Variante.
        let barrierCount: Int
        /// Davon fürs eigene Profil kritisch (`shouldWarn`).
        let criticalCount: Int

        var id: UUID { route.id }
    }

    /// Wegvarianten zum gewählten Ziel (leer, solange keins gewählt ist).
    @Published private(set) var routeOptions: [RouteOption] = []
    @Published private(set) var isLoadingRouteOptions = false
    /// Ziel, zu dem die Varianten berechnet wurden.
    @Published private(set) var routeOptionsTarget: POI?
    /// Fehler der Variantenberechnung. Bewusst nicht der Vollbild-Zustand
    /// "Keine Route gefunden": Der läge hinter dem offenen Routen-Sheet.
    @Published private(set) var routeOptionsError: String?

    /// Berechnet die Wegvarianten zum Ziel für das Routen-Sheet.
    func loadRouteOptions(to poi: POI, profile: UserProfile) async {
        routeOptionsTarget = poi
        routeOptions = []
        routeOptionsError = nil

        guard let startLocation = locationService.currentLocation else {
            routeOptionsError = "Dein Standort ist unbekannt – ohne Startpunkt lässt sich keine Route berechnen."
            return
        }

        isLoadingRouteOptions = true
        defer { isLoadingRouteOptions = false }

        do {
            let routes = try await RouteService.routeOptions(
                from: startLocation.coordinate,
                to: CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude),
                destinationName: poi.name,
                profile: profile
            )
            routeOptions = routes.map { route in
                let onRoute = barriers(on: route)
                return RouteOption(
                    route: route,
                    barrierCount: onRoute.count,
                    criticalCount: onRoute.filter { shouldWarn(barrier: $0, profile: profile) }.count
                )
            }
        } catch {
            routeOptionsError = error.localizedDescription
        }
    }

    /// Startet die Navigation mit einer im Routen-Sheet gewählten Variante –
    /// ohne Neuberechnung, sonst käme womöglich eine andere Strecke heraus als
    /// die, die man ausgesucht hat.
    func startNavigation(with option: RouteOption, to poi: POI, profile: UserProfile) {
        activate(route: option.route, to: poi, profile: profile)
        clearRouteOptions()
    }

    /// Leert die Variantenauswahl (Sheet geschlossen oder Ziel gewechselt).
    func clearRouteOptions() {
        routeOptions = []
        routeOptionsTarget = nil
        routeOptionsError = nil
    }

    /// Barrieren im Korridor einer beliebigen – auch noch nicht aktiven –
    /// Route. Gleiche Korridorbreite wie bei der aktiven Navigation.
    func barriers(on route: ActiveRoute) -> [Barrier] {
        let corridor = corridorM(for: route.kind)
        let path = RouteService.path(of: route)
        return filteredBarriers.filter { barrier in
            RouteService.offsetAndAlong(of: barrier.coordinate, on: path).offsetM <= corridor
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
            .map(\.coordinate)

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