// RouteService.swift
// ARMikronav
//
// Berechnet rollstuhlgerechte Routen auf OpenStreetMap-Daten und liefert den
// Fortschritt (Restdistanz/Restzeit) entlang einer aktiven Route.
//
// Grundlage ist das OSM-Rollstuhl-Routing, wie es das OSM-Wiki beschreibt
// (https://wiki.openstreetmap.org/wiki/Wheelchair_routing): OpenRouteService
// der GIScience-Gruppe Heidelberg, Profil "wheelchair". Es wertet genau die
// dort gelisteten Tags aus – incline, sloped_curb/kerb:height, width, surface,
// smoothness, tracktype, wheelchair=yes/limited/no – und bekommt die
// persönlichen Limits aus dem UserProfile als Restriktionen mit.
//
// Gerechnet wird in drei Stufen (siehe `route`): eigene Limits → gelockerte
// Vorgaben nach DIN 18024-1 (AccessibilityStandard) → erst als letzter
// Notnagel die MapKit-Fussgängerroute. Welche Stufe gegriffen hat, steht im
// RouteKind, damit die UI es ausweisen kann.
//
// Die Route wird als Wegpunkt-Liste gehalten, damit Karte (MapPolyline)
// und AR-Rendering (ARRouteRenderer) dieselbe Geometrie verwenden.
//
// Fahrzeiten kommen NICHT von den Routing-Diensten: sowohl ORS als auch
// MapKit rechnen mit Fussgänger-Tempo (~5 km/h). Für Rollstuhlnutzende ist
// das je nach Antrieb deutlich zu schnell (Handrollstuhl) oder zu langsam
// (Elektrorollstuhl). Dauer und Ankunftszeit werden deshalb aus der
// Streckenlänge und der im Profil hinterlegten eigenen Geschwindigkeit
// (`effectiveTravelSpeedKmh`) berechnet.

import Foundation
import MapKit
import CoreLocation
import simd

/// Wie die Route berechnet wurde.
enum RouteKind: Equatable {
    /// Rollstuhlgerechte OSM-Route (OpenRouteService-Profil "wheelchair") mit
    /// den persönlichen Limits aus dem UserProfile.
    case wheelchair
    /// Rollstuhlgerechte OSM-Route mit gelockerten Vorgaben: Mit den eigenen
    /// Limits fand sich kein Weg (oder nur ein absurder Umweg), deshalb wurden
    /// die Schwellen auf die Norm-Grenzwerte geweitet. Weiterhin OSM-Routing
    /// über Gehwege, nicht die Fussgängerroute.
    case wheelchairRelaxed
    /// MapKit-Fussgängerroute als letzter Notnagel – OSM-Rollstuhl-Tags
    /// (Oberfläche, Bordstein, Breite, Steigung) fliessen nicht ein.
    case walkingFallback

    /// Beruht die Route auf dem OSM-Rollstuhl-Routing (und damit auf den
    /// Rollstuhl-Tags aus OpenStreetMap)?
    var usesOSMWheelchairRouting: Bool { self != .walkingFallback }

    /// Symbol für den Manöver-Kreis im Routen-Panel.
    var symbolName: String {
        usesOSMWheelchairRouting ? "figure.roll" : "figure.walk"
    }
}

/// Eine berechnete Route zu einem Ziel (POI).
struct ActiveRoute: Identifiable, Equatable {
    let id: UUID
    let destinationName: String
    let destinationCoordinate: CLLocationCoordinate2D
    /// Wegpunkte des Routen-Polylines (Start → Ziel).
    let coordinates: [CLLocationCoordinate2D]
    let totalDistanceM: CLLocationDistance
    let expectedTravelTimeS: TimeInterval
    let kind: RouteKind
    /// Turn-by-turn-Schritte der Route (Manöver + Strasse/Weg) für die
    /// Listenansicht während der Navigation. Leer, wenn der Routing-Dienst
    /// keine Schrittdaten liefert.
    let steps: [RouteStep]

    init(
        id: UUID = UUID(),
        destinationName: String,
        destinationCoordinate: CLLocationCoordinate2D,
        coordinates: [CLLocationCoordinate2D],
        totalDistanceM: CLLocationDistance,
        expectedTravelTimeS: TimeInterval,
        kind: RouteKind = .wheelchair,
        steps: [RouteStep] = []
    ) {
        self.id = id
        self.destinationName = destinationName
        self.destinationCoordinate = destinationCoordinate
        self.coordinates = coordinates
        self.totalDistanceM = totalDistanceM
        self.expectedTravelTimeS = expectedTravelTimeS
        self.kind = kind
        self.steps = steps
    }

    static func == (lhs: ActiveRoute, rhs: ActiveRoute) -> Bool {
        lhs.id == rhs.id
    }
}

/// Verbleibende Distanz und Zeit auf der aktiven Route.
struct RouteProgress: Equatable {
    let remainingDistanceM: CLLocationDistance
    let remainingTimeS: TimeInterval

    /// Ankunft, sobald weniger als 10 m Restweg übrig sind.
    var hasArrived: Bool { remainingDistanceM < 10 }
}

/// Fusspunkt des Standorts auf der Route: die Position auf der Polyline
/// (violette Linie) plus der seitliche Abstand des Rohstandorts zu ihr.
struct RouteSnap {
    /// Auf die Route projizierter Punkt (auf der Linie).
    let coordinate: CLLocationCoordinate2D
    /// Seitlicher Abstand des Rohstandorts zur Route in Metern.
    let offsetM: CLLocationDistance
}

/// Verortung eines Standorts auf der Route: auf welchem Segment er liegt, wie
/// weit er seitlich daneben liegt und wie viel Weg davor bzw. dahinter liegt.
/// Gemeinsame Grundlage für Restweg, Einrasten, Abbiege-Ansage und
/// Kartendrehung – damit alle vier dieselbe Stelle der Route meinen.
struct RouteFix {
    /// Index des Segments (Wegpunkt i → i+1), auf das projiziert wurde.
    let segmentIndex: Int
    /// Auf die Route projizierter Punkt (auf der Linie).
    let coordinate: CLLocationCoordinate2D
    /// Seitlicher Abstand des Rohstandorts zur Route in Metern.
    let offsetM: CLLocationDistance
    /// Weglänge vom Routenstart bis zum Fusspunkt.
    let alongM: CLLocationDistance
    /// Weglänge vom Fusspunkt bis zum Ziel.
    let remainingM: CLLocationDistance
}

/// Richtung des nächsten Manövers entlang der Route (aus der Polyline-
/// Geometrie abgeleitet). Positiver Winkel = Linkskurve.
enum ManeuverDirection: Equatable {
    case straight
    case slightLeft
    case slightRight
    case left
    case right
    /// Blickrichtung zeigt (annähernd) entgegengesetzt zur Route – man muss
    /// sich umdrehen. Entsteht nur aus der egozentrischen Ausrichtung, nicht
    /// aus der Routengeometrie.
    case turnAround

    var symbolName: String {
        switch self {
        case .straight:    return "arrow.up"
        case .slightLeft:  return "arrow.up.left"
        case .slightRight: return "arrow.up.right"
        case .left:        return "arrow.turn.up.left"
        case .right:       return "arrow.turn.up.right"
        case .turnAround:  return "arrow.uturn.down"
        }
    }

    /// Verb-Phrase für die Anweisung ("In 40 m …").
    var phrase: String {
        switch self {
        case .straight:    return "geradeaus weiter"
        case .slightLeft:  return "leicht links halten"
        case .slightRight: return "leicht rechts halten"
        case .left:        return "links abbiegen"
        case .right:       return "rechts abbiegen"
        case .turnAround:  return "umdrehen"
        }
    }
}

/// Nächstes Manöver auf der aktiven Route: Richtung plus Distanz vom
/// aktuellen Standort bis zum Abbiegepunkt (bzw. bis zum Ziel bei geradeaus).
struct RouteManeuver: Equatable {
    let direction: ManeuverDirection
    let distanceM: CLLocationDistance

    /// Fertige Anweisung, z. B. "In 40 m links abbiegen" oder "Jetzt
    /// rechts abbiegen" kurz vor dem Abbiegepunkt.
    var instruction: String {
        if direction == .straight {
            return "Geradeaus weiter"
        }
        // Blickt man entgegengesetzt zur Route, ist die klare Ansage "umdrehen"
        // (kein "jetzt links/rechts" – die Richtung liegt hinter einem).
        if direction == .turnAround {
            return "Bitte umdrehen"
        }
        if distanceM < 15 {
            return "Jetzt \(direction.phrase)"
        }
        return "In \(DistanceFormatter.string(fromMeters: distanceM)) \(direction.phrase)"
    }
}

/// Manöver-Typ eines Routenschritts (aus den OpenRouteService-Instruktions-
/// typen bzw. aus dem Text der MapKit-Fallback-Route abgeleitet). Liefert
/// Icon und deutsche Kurzanweisung für die Turn-by-turn-Liste.
enum StepManeuver: Equatable {
    case depart
    case arrive
    case straight
    case slightLeft
    case slightRight
    case left
    case right
    case sharpLeft
    case sharpRight
    case keepLeft
    case keepRight
    case uTurn
    case roundabout

    /// SF-Symbol des Manövers (bewusst nur breit verfügbare Symbolnamen).
    var symbolName: String {
        switch self {
        case .depart:      return "figure.roll"
        case .arrive:      return "mappin.circle.fill"
        case .straight:    return "arrow.up"
        case .slightLeft:  return "arrow.up.left"
        case .slightRight: return "arrow.up.right"
        case .left:        return "arrow.turn.up.left"
        case .right:       return "arrow.turn.up.right"
        case .sharpLeft:   return "arrow.uturn.left"
        case .sharpRight:  return "arrow.uturn.right"
        case .keepLeft:    return "arrow.up.left"
        case .keepRight:   return "arrow.up.right"
        case .uTurn:       return "arrow.uturn.down"
        case .roundabout:  return "arrow.clockwise"
        }
    }

    /// Kurzanweisung ("Links abbiegen", "Geradeaus weiter", …).
    var phrase: String {
        switch self {
        case .depart:      return "Start"
        case .arrive:      return "Ziel erreicht"
        case .straight:    return "Geradeaus weiter"
        case .slightLeft:  return "Leicht links halten"
        case .slightRight: return "Leicht rechts halten"
        case .left:        return "Links abbiegen"
        case .right:       return "Rechts abbiegen"
        case .sharpLeft:   return "Scharf links abbiegen"
        case .sharpRight:  return "Scharf rechts abbiegen"
        case .keepLeft:    return "Links halten"
        case .keepRight:   return "Rechts halten"
        case .uTurn:       return "Wenden"
        case .roundabout:  return "Kreisverkehr"
        }
    }

    /// Abbildung der OpenRouteService-Instruktionstypen (0–13).
    /// https://openrouteservice.org/dev/#/api-docs/v2/directions
    static func fromORSType(_ type: Int) -> StepManeuver {
        switch type {
        case 0:      return .left
        case 1:      return .right
        case 2:      return .sharpLeft
        case 3:      return .sharpRight
        case 4:      return .slightLeft
        case 5:      return .slightRight
        case 6:      return .straight
        case 7, 8:   return .roundabout
        case 9:      return .uTurn
        case 10:     return .arrive
        case 11:     return .depart
        case 12:     return .keepLeft
        case 13:     return .keepRight
        default:     return .straight
        }
    }

    /// Best-effort-Ableitung aus dem Anweisungstext der MapKit-Fallback-Route
    /// (die keine strukturierten Manöverdaten liefert).
    static func fromText(_ text: String, isFirst: Bool) -> StepManeuver {
        let lower = text.lowercased()
        if isFirst, lower.isEmpty { return .depart }
        if lower.contains("ziel") || lower.contains("angekommen") || lower.contains("erreicht") {
            return .arrive
        }
        if lower.contains("wenden") { return .uTurn }
        if lower.contains("links") {
            return lower.contains("leicht") ? .slightLeft : .left
        }
        if lower.contains("rechts") {
            return lower.contains("leicht") ? .slightRight : .right
        }
        return .straight
    }
}

/// Ein Schritt der Turn-by-turn-Liste: das Manöver plus die Strasse/der Weg,
/// dem man bis zum nächsten Manöver folgt ("wo durch"). Über `way_points`
/// (ORS) an die Routengeometrie gekoppelt, damit sich der aktuelle Schritt
/// aus der Position bestimmen lässt.
struct RouteStep: Identifiable, Equatable {
    /// Reihenfolge-Index in der Route (0 = Start).
    let id: Int
    /// Manöver-Richtung (liefert Icon und Kurzanweisung).
    let maneuver: StepManeuver
    /// Strassen-/Wegname des Schritts – nil, wenn unbenannt.
    let streetName: String?
    /// Vollständige Anweisung, falls der Routing-Dienst nur Text liefert
    /// (MapKit-Fallback). Ersetzt dann die aus Manöver + Strasse gebildete.
    let providedText: String?
    /// Länge dieses Schritts (Meter).
    let distanceM: CLLocationDistance
    /// Dauer dieses Schritts (Sekunden).
    let durationS: TimeInterval
    /// Startkoordinate des Schritts (dort wird das Manöver ausgeführt).
    let coordinate: CLLocationCoordinate2D

    init(
        id: Int,
        maneuver: StepManeuver,
        streetName: String? = nil,
        providedText: String? = nil,
        distanceM: CLLocationDistance,
        durationS: TimeInterval = 0,
        coordinate: CLLocationCoordinate2D
    ) {
        self.id = id
        self.maneuver = maneuver
        self.streetName = streetName
        self.providedText = providedText
        self.distanceM = distanceM
        self.durationS = durationS
        self.coordinate = coordinate
    }

    /// Primäre Anweisung der Zeile ("Links abbiegen").
    var instruction: String {
        if let providedText, !providedText.isEmpty { return providedText }
        return maneuver.phrase
    }

    /// "Wo durch" – Strasse/Weg unter der Anweisung (nil = keine Angabe).
    /// Bei Text-Schritten (Fallback) steckt die Strasse schon in `instruction`.
    var wayText: String? {
        if providedText != nil { return nil }
        guard let streetName else { return nil }
        switch maneuver {
        case .arrive, .depart, .straight: return streetName
        default: return "auf \(streetName)"
        }
    }

    static func == (lhs: RouteStep, rhs: RouteStep) -> Bool {
        lhs.id == rhs.id
            && lhs.maneuver == rhs.maneuver
            && lhs.streetName == rhs.streetName
            && lhs.providedText == rhs.providedText
            && lhs.distanceM == rhs.distanceM
    }
}

enum RouteService {
    enum RouteError: LocalizedError {
        case noRoute
        case orsNotConfigured
        case orsRequestFailed

        var errorDescription: String? {
            switch self {
            case .noRoute:
                return "Keine Route gefunden."
            case .orsNotConfigured:
                return "OpenRouteService-API-Key fehlt (Secrets.swift)."
            case .orsRequestFailed:
                return "Rollstuhl-Routing nicht erreichbar."
            }
        }
    }

    private static let orsDirectionsURL =
        URL(string: "https://api.openrouteservice.org/v2/directions/wheelchair/geojson")!

    // MARK: - Fahrzeit mit eigenem Tempo

    /// Fahrzeit (Sekunden) für eine Strecke mit der eigenen Geschwindigkeit aus
    /// dem Profil. Ersetzt die Fussgänger-Dauer der Routing-Dienste, damit
    /// Restzeit und Ankunftszeit zum tatsächlichen Tempo im Rollstuhl passen.
    static func travelTime(
        forMeters meters: CLLocationDistance,
        profile: UserProfile
    ) -> TimeInterval {
        let speedMS = profile.effectiveTravelSpeedMS
        guard speedMS > 0, meters > 0 else { return 0 }
        return meters / speedMS
    }

    // MARK: - Plausibilität einer Route

    /// Luftlinie (Meter), unterhalb derer das Ziel als "praktisch nebenan"
    /// gilt – dort fällt ein grosser Umweg sofort auf.
    private static let shortTripBeelineM: CLLocationDistance = 400
    /// Verhältnis Routenlänge zu Luftlinie, ab dem die Rollstuhl-Route als
    /// unplausibel gilt.
    private static let implausibleDetourFactor = 6.0
    /// Sockel obendrauf, damit normale Umwege auf kurzen Strecken (Hauseingang
    /// auf der anderen Seite, Treppe umfahren) nicht anschlagen.
    private static let implausibleDetourMarginM: CLLocationDistance = 250
    /// So viel kürzer muss die Fussgängerroute sein, damit sie eine als
    /// unplausibel erkannte Rollstuhl-Route ersetzt.
    private static let plausibleFallbackFactor = 0.6

    /// Ist die berechnete Route gemessen an der Luftlinie unplausibel lang?
    /// Genau der Fall aus dem Feldtest: Das Ziel liegt 40 m entfernt auf der
    /// anderen Strassenseite, die Route führt aber 1,9 km über die übernächste
    /// Brücke – typischerweise, weil der Startpunkt aus einem GPS-Ausreisser
    /// stammt oder die Profil-Limits das direkte Wegstück ausschliessen.
    static func isImplausibleDetour(
        routeDistanceM: CLLocationDistance,
        beelineM: CLLocationDistance
    ) -> Bool {
        guard beelineM < shortTripBeelineM else { return false }
        return routeDistanceM > beelineM * implausibleDetourFactor + implausibleDetourMarginM
    }

    /// Berechnet die Route zum Ziel in drei Stufen – die Fussgängerroute ist
    /// bewusst nur der letzte Notnagel, gefahren wird auf OSM-Rollstuhl-Daten:
    ///
    /// 1. OSM-Rollstuhl-Routing (ORS-Profil "wheelchair") mit den
    ///    persönlichen Limits aus dem Profil.
    /// 2. Schlägt das fehl (kein Weg innerhalb der eigenen Limits, Netzfehler)
    ///    oder ergibt es einen absurden Umweg: dasselbe OSM-Routing mit
    ///    gelockerten Vorgaben (Norm-Grenzwerte statt persönlicher Limits).
    ///    So folgt die Route weiterhin Gehwegen, Absenkungen und Oberflächen
    ///    aus OSM.
    /// 3. Sind BEIDE OSM-Routen nur Riesenumwege (oder kam gar keine zustande),
    ///    kommt zusätzlich die MapKit-Fussgängerroute ins Rennen; welche
    ///    Kandidatin gewinnt, entscheidet `preferredRoute`.
    ///
    /// Jede Stufe wird auf Plausibilität geprüft – die Prüfung stammt aus dem
    /// Feldtest: Liegt das Ziel 40 m entfernt und führt die Route 1,9 km über
    /// die übernächste Brücke, ist lieber ein gekennzeichneter kurzer Weg
    /// brauchbar als ein perfekter, aber unbenutzbarer Umweg.
    static func route(
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        profile: UserProfile
    ) async throws -> ActiveRoute {
        let beelineM = CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(
                from: CLLocation(latitude: destination.latitude, longitude: destination.longitude)
            )

        // Stufe 1: OSM-Rollstuhl-Routing mit den eigenen Limits.
        let strict = try? await wheelchairRoute(
            from: start,
            to: destination,
            destinationName: destinationName,
            profile: profile
        )
        if let strict,
           !isImplausibleDetour(routeDistanceM: strict.totalDistanceM, beelineM: beelineM) {
            return strict
        }

        // Stufe 2: dasselbe OSM-Routing, aber mit gelockerten Vorgaben.
        let relaxed = try? await wheelchairRoute(
            from: start,
            to: destination,
            destinationName: destinationName,
            profile: profile,
            relaxed: true
        )
        if let relaxed,
           !isImplausibleDetour(routeDistanceM: relaxed.totalDistanceM, beelineM: beelineM) {
            return relaxed
        }

        // Stufe 3: Beide OSM-Routen sind Riesenumwege (oder gar keine kam
        // zustande) – jetzt zählt auch die Fussgängerroute als Kandidatin.
        let walking = try? await walkingRoute(
            from: start,
            to: destination,
            destinationName: destinationName,
            profile: profile
        )
        guard let best = preferredRoute(
            strict: strict,
            relaxed: relaxed,
            walking: walking,
            beelineM: beelineM
        ) else {
            throw RouteError.noRoute
        }
        return best
    }

    /// Wählt aus den vorliegenden Kandidaten die Route, die angeboten wird.
    /// Bewusst als reine Funktion ohne Netzzugriff, damit die Auswahl testbar
    /// ist – hier entscheidet sich, ob jemand mit einem 2-km-Umweg zu einem
    /// Ziel geschickt wird, das 150 m entfernt liegt.
    ///
    /// Reihenfolge: plausible Route mit den eigenen Limits, dann plausible
    /// gelockerte OSM-Route, sonst die kürzeste OSM-Route – und die
    /// Fussgängerroute nur, wenn sie deutlich kürzer ist als diese.
    static func preferredRoute(
        strict: ActiveRoute?,
        relaxed: ActiveRoute?,
        walking: ActiveRoute?,
        beelineM: CLLocationDistance
    ) -> ActiveRoute? {
        func isPlausible(_ route: ActiveRoute) -> Bool {
            !isImplausibleDetour(routeDistanceM: route.totalDistanceM, beelineM: beelineM)
        }

        if let strict, isPlausible(strict) { return strict }
        if let relaxed, isPlausible(relaxed) { return relaxed }

        // Keine der OSM-Routen ist plausibel: die kürzere der beiden ist der
        // Bezugswert für den Vergleich mit der Fussgängerroute.
        let bestOSMRoute = [strict, relaxed]
            .compactMap { $0 }
            .min { $0.totalDistanceM < $1.totalDistanceM }

        guard let walking else { return bestOSMRoute }
        guard let bestOSMRoute else { return walking }
        return walking.totalDistanceM < bestOSMRoute.totalDistanceM * plausibleFallbackFactor
            ? walking
            : bestOSMRoute
    }

    // MARK: - Rollstuhl-Route (OpenRouteService)

    /// Fragt das OSM-Rollstuhl-Routing an (ORS-Profil "wheelchair", das auf den
    /// im OSM-Wiki beschriebenen Rollstuhl-Tags aufsetzt). Die Restriktionen
    /// kommen aus dem UserProfile: max. Steigung (`incline`), max.
    /// Bordsteinhöhe (`sloped_curb`/`kerb:height`), benötigte Breite (`width`,
    /// inkl. Begleitungs-Bonus via effective*-Werte), Oberfläche (`surface`),
    /// Ebenheit (`smoothness`) und Wegequalität (`tracktype`).
    ///
    /// `relaxed` weitet die Vorgaben auf die Norm-Grenzwerte (DIN 18024-1,
    /// siehe AccessibilityStandard) – für den Fall, dass sich mit den eigenen
    /// Limits gar kein Weg finden lässt. Wege, die OSM als nicht
    /// rollstuhlgerecht führt (`wheelchair=no`), bleiben auch dann gesperrt.
    ///
    /// `avoiding` sind Barrieren-Koordinaten, die die Route umgehen soll
    /// (Tagesform: z. B. Steigung, die bei Hitze nicht machbar ist) – sie
    /// werden als avoid_polygons an ORS übergeben.
    static func wheelchairRoute(
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        profile: UserProfile,
        avoiding: [CLLocationCoordinate2D] = [],
        relaxed: Bool = false
    ) async throws -> ActiveRoute {
        let apiKey = Secrets.openRouteServiceAPIKey
        guard !apiKey.isEmpty else { throw RouteError.orsNotConfigured }

        var request = URLRequest(url: orsDirectionsURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body = ORSDirectionsRequest(
            coordinates: [
                [start.longitude, start.latitude],
                [destination.longitude, destination.latitude],
            ],
            options: .init(
                profileParams: .init(
                    restrictions: .init(profile: profile, relaxed: relaxed)
                ),
                avoidPolygons: ORSDirectionsRequest.AvoidPolygons(around: avoiding),
                avoidFeatures: ORSDirectionsRequest.excludedFeatures
            )
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RouteError.orsRequestFailed
        }

        let geoJSON = try JSONDecoder().decode(ORSDirectionsResponse.self, from: data)
        guard let feature = geoJSON.features.first,
              feature.geometry.coordinates.count >= 2 else {
            throw RouteError.noRoute
        }

        let coordinates = feature.geometry.coordinates.map {
            CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
        }

        // Dauer bewusst aus der eigenen Geschwindigkeit statt aus
        // `summary.duration` – ORS rechnet auch im Rollstuhl-Profil mit
        // Fussgänger-Tempo.
        return ActiveRoute(
            destinationName: destinationName,
            destinationCoordinate: destination,
            coordinates: coordinates,
            totalDistanceM: feature.properties.summary.distance,
            expectedTravelTimeS: travelTime(
                forMeters: feature.properties.summary.distance,
                profile: profile
            ),
            kind: relaxed ? .wheelchairRelaxed : .wheelchair,
            steps: orsSteps(
                from: feature.properties.segments,
                coordinates: coordinates,
                profile: profile
            )
        )
    }

    /// OSM-Rollstuhl-Route, die die übergebenen Barrieren umgeht: zuerst mit
    /// den eigenen Limits, sonst mit gelockerten Vorgaben. Bewusst ohne
    /// Fussgänger-Fallback – der würde die zu umgehende Barriere gar nicht
    /// kennen und wieder direkt über sie führen.
    static func wheelchairRoute(
        avoiding barriers: [CLLocationCoordinate2D],
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        profile: UserProfile
    ) async throws -> ActiveRoute {
        do {
            return try await wheelchairRoute(
                from: start,
                to: destination,
                destinationName: destinationName,
                profile: profile,
                avoiding: barriers
            )
        } catch {
            return try await wheelchairRoute(
                from: start,
                to: destination,
                destinationName: destinationName,
                profile: profile,
                avoiding: barriers,
                relaxed: true
            )
        }
    }

    /// Baut die Turn-by-turn-Schritte aus den ORS-Segmenten. Jeder Schritt
    /// referenziert über `way_points` seinen Startpunkt in der Routengeometrie;
    /// die Schrittdauer rechnet – wie die Gesamtdauer – mit dem eigenen Tempo.
    private static func orsSteps(
        from segments: [ORSDirectionsResponse.Segment]?,
        coordinates: [CLLocationCoordinate2D],
        profile: UserProfile
    ) -> [RouteStep] {
        guard let segments else { return [] }
        var steps: [RouteStep] = []
        for segment in segments {
            for step in segment.steps {
                let startIndex = step.wayPoints.first ?? 0
                let coordinate = coordinates.indices.contains(startIndex)
                    ? coordinates[startIndex]
                    : (coordinates.first ?? kCLLocationCoordinate2DInvalid)
                steps.append(
                    RouteStep(
                        id: steps.count,
                        maneuver: StepManeuver.fromORSType(step.type),
                        streetName: cleanedStreetName(step.name),
                        distanceM: step.distance,
                        durationS: travelTime(forMeters: step.distance, profile: profile),
                        coordinate: coordinate
                    )
                )
            }
        }
        return steps
    }

    /// ORS liefert "-" für unbenannte Wege – zu nil normalisieren.
    private static func cleanedStreetName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != "-" else { return nil }
        return trimmed
    }

    /// Berechnet eine Fussgänger-Route via MapKit (Fallback ohne
    /// Barrieren-Berücksichtigung). Mit `profile` wird die Fahrzeit aus der
    /// eigenen Geschwindigkeit gerechnet statt aus MapKits Fussgänger-Tempo;
    /// ohne Profil bleibt es bei MapKits Schätzung.
    static func walkingRoute(
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        profile: UserProfile? = nil
    ) async throws -> ActiveRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw RouteError.noRoute }

        return ActiveRoute(
            destinationName: destinationName,
            destinationCoordinate: destination,
            coordinates: route.polyline.coordinateList(),
            totalDistanceM: route.distance,
            expectedTravelTimeS: profile.map {
                travelTime(forMeters: route.distance, profile: $0)
            } ?? route.expectedTravelTime,
            kind: .walkingFallback,
            steps: walkingSteps(from: route, profile: profile)
        )
    }

    /// Baut die Turn-by-turn-Schritte aus einer MapKit-Route. MKRoute liefert
    /// nur Anweisungstext (keine strukturierten Manöver) – das Manöver-Icon
    /// wird best-effort aus dem Text abgeleitet, der Text selbst angezeigt.
    /// Schritte ohne Anweisung (ausser dem Start) werden übersprungen.
    private static func walkingSteps(
        from route: MKRoute,
        profile: UserProfile? = nil
    ) -> [RouteStep] {
        var steps: [RouteStep] = []
        for (index, step) in route.steps.enumerated() {
            let text = step.instructions.trimmingCharacters(in: .whitespaces)
            let isFirst = index == 0
            guard isFirst || !text.isEmpty else { continue }
            let coordinate = step.polyline.coordinateList().first
                ?? route.polyline.coordinateList().first
                ?? kCLLocationCoordinate2DInvalid
            steps.append(
                RouteStep(
                    id: steps.count,
                    maneuver: StepManeuver.fromText(text, isFirst: isFirst),
                    providedText: isFirst && text.isEmpty ? "Start" : text,
                    distanceM: step.distance,
                    durationS: profile.map {
                        travelTime(forMeters: step.distance, profile: $0)
                    } ?? 0,
                    coordinate: coordinate
                )
            )
        }
        return steps
    }

    // MARK: - Verortung auf der Route

    /// Wie weit der Fusspunkt hinter dem bisher erreichten Punkt liegen darf,
    /// ohne dass es als Rückwärtssprung zählt (GPS-Rauschen, Stehenbleiben).
    private static let anchorBacktrackToleranceM = 30.0
    /// Wie weit der Fusspunkt vor dem bisher erreichten Punkt liegen darf.
    /// Zwischen zwei Standort-Updates legt man höchstens ein paar Dutzend
    /// Meter zurück; alles darüber wäre ein Sprung auf einen anderen
    /// Routenabschnitt, der zufällig in der Nähe verläuft.
    private static let anchorForwardWindowM = 250.0
    /// Aufschlag je Meter, den ein Kandidat ausserhalb dieses Fensters liegt.
    /// Bewusst < 1, damit ein klar näher liegendes Segment weiterhin gewinnen
    /// kann – der Anker lenkt die Wahl, er erzwingt sie nicht.
    private static let anchorWindowPenaltyPerM = 0.35

    /// Fusspunkt in lokalen Ost/Nord-Metern (Standort = Ursprung).
    private struct ProjectedFix {
        let segmentIndex: Int
        let projection: SIMD2<Double>
        let offsetM: Double
        let alongM: Double
        let remainingM: Double
    }

    /// Route als lokales Ost/Nord-Meter-Koordinatensystem um `origin`
    /// (der Bezugspunkt selbst liegt im Ursprung 0,0).
    private static func routePoints(
        of route: ActiveRoute,
        relativeTo origin: CLLocationCoordinate2D
    ) -> [SIMD2<Double>] {
        route.coordinates.map { metersEastNorth(of: $0, relativeTo: origin) }
    }

    /// Projiziert den Ursprung (0,0) auf die Polyline.
    ///
    /// Ohne `alongAnchorM` gewinnt schlicht das nächstgelegene Segment. Das
    /// genügt, solange die Route sich nicht selbst nahekommt – tut sie es
    /// (Umweg über die nächste Brücke, Hin- und Rückweg in derselben Gasse,
    /// Parallelgassen der Altstadt), rastet die Projektion sonst auf dem
    /// falschen Ast ein: Restweg, Kartendrehung und Abbiege-Ansage kippen dann
    /// schlagartig, bis hin zum dauerhaften "Bitte umdrehen".
    ///
    /// Mit `alongAnchorM` (bisher zurückgelegte Weglänge) werden Kandidaten
    /// ausserhalb eines Fensters um diesen Wert mit einem Aufschlag bestraft.
    /// Die Projektion bleibt damit vorwärtsgerichtet und stabil.
    private static func project(
        _ points: [SIMD2<Double>],
        alongAnchorM: CLLocationDistance? = nil
    ) -> ProjectedFix? {
        guard points.count >= 2 else { return nil }

        // prefix[i] = Weglänge vom Start bis Punkt i.
        var prefix = [Double](repeating: 0, count: points.count)
        for i in 1..<points.count {
            prefix[i] = prefix[i - 1] + simd_distance(points[i - 1], points[i])
        }
        let totalLength = prefix[points.count - 1]

        var best: ProjectedFix?
        var bestScore = Double.greatestFiniteMagnitude

        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let ab = b - a
            let lengthSquared = simd_length_squared(ab)
            let t = lengthSquared > 0 ? min(1, max(0, simd_dot(-a, ab) / lengthSquared)) : 0
            let projected = a + t * ab
            let offset = simd_length(projected)
            let along = prefix[i] + simd_distance(a, projected)

            var score = offset
            if let alongAnchorM {
                let behind = (alongAnchorM - anchorBacktrackToleranceM) - along
                let ahead = along - (alongAnchorM + anchorForwardWindowM)
                let outside = max(0, max(behind, ahead))
                score += outside * anchorWindowPenaltyPerM
            }

            if score < bestScore {
                bestScore = score
                best = ProjectedFix(
                    segmentIndex: i,
                    projection: projected,
                    offsetM: offset,
                    alongM: along,
                    remainingM: max(0, totalLength - along)
                )
            }
        }
        return best
    }

    /// Verortet den Standort auf der Route (Segment, Fusspunkt, seitlicher
    /// Abstand, Weg davor/dahinter). `alongAnchorM` hält die Projektion
    /// vorwärtsgerichtet – siehe `project`.
    static func locate(
        on route: ActiveRoute,
        at location: CLLocation,
        alongAnchorM: CLLocationDistance? = nil
    ) -> RouteFix? {
        let origin = location.coordinate
        let points = routePoints(of: route, relativeTo: origin)
        guard let fix = project(points, alongAnchorM: alongAnchorM) else { return nil }
        return RouteFix(
            segmentIndex: fix.segmentIndex,
            coordinate: coordinate(from: origin, east: fix.projection.x, north: fix.projection.y),
            offsetM: fix.offsetM,
            alongM: fix.alongM,
            remainingM: fix.remainingM
        )
    }

    /// Projiziert den Standort auf die Route und summiert die verbleibenden
    /// Segmentlängen. Restzeit anteilig zur erwarteten Gesamtzeit.
    static func progress(
        of route: ActiveRoute,
        at location: CLLocation,
        alongAnchorM: CLLocationDistance? = nil
    ) -> RouteProgress {
        let points = routePoints(of: route, relativeTo: location.coordinate)
        guard let fix = project(points, alongAnchorM: alongAnchorM) else {
            let destination = CLLocation(
                latitude: route.destinationCoordinate.latitude,
                longitude: route.destinationCoordinate.longitude
            )
            let remaining = location.distance(from: destination)
            return RouteProgress(
                remainingDistanceM: remaining,
                remainingTimeS: remainingTime(for: remaining, on: route)
            )
        }
        return RouteProgress(
            remainingDistanceM: fix.remainingM,
            remainingTimeS: remainingTime(for: fix.remainingM, on: route)
        )
    }

    /// Projiziert den Standort auf die Route und gibt den Fusspunkt (auf der
    /// violetten Linie) samt seitlichem Abstand zurück. Damit lässt sich der
    /// Standortpunkt auf der Karte auf die Route "einrasten", solange man nah
    /// genug an ihr ist – so springt er nicht mehr neben der Linie herum
    /// (GPS-Rauschen und Mehrwegempfang in den engen, hohen Altstadt-Gassen).
    /// Der Aufrufer entscheidet über `offsetM`, ob eingerastet oder der
    /// Rohstandort gezeigt wird.
    static func snappedLocation(
        on route: ActiveRoute,
        at location: CLLocation,
        alongAnchorM: CLLocationDistance? = nil
    ) -> RouteSnap {
        let origin = location.coordinate
        let points = routePoints(of: route, relativeTo: origin)
        guard let fix = project(points, alongAnchorM: alongAnchorM) else {
            return RouteSnap(coordinate: origin, offsetM: 0)
        }
        // Fusspunkt (Meter Ost/Nord relativ zum Standort) zurück in Koordinaten.
        return RouteSnap(
            coordinate: coordinate(from: origin, east: fix.projection.x, north: fix.projection.y),
            offsetM: fix.offsetM
        )
    }

    /// Abschnitt der Route, der im AR-Bild dargestellt wird: beginnt am
    /// Fusspunkt des Standorts auf der Route und reicht `aheadM` Meter voraus.
    ///
    /// Der AR-Pfad braucht nur den Weg, der tatsächlich vor einem liegt. Die
    /// ganze Route zu rendern kostet – bei 2 m Stützpunktabstand – hunderte
    /// Entities (Ruckeln, thermisches Drosseln) und legt zudem den bereits
    /// zurückgelegten Teil hinter einem im Bild ab. Der zurückgegebene Abschnitt
    /// startet exakt auf der Linie unter den eigenen Rädern, damit der Pfad
    /// nahtlos an der aktuellen Position ansetzt.
    static func upcomingCoordinates(
        of route: ActiveRoute,
        from location: CLLocationCoordinate2D,
        aheadM: CLLocationDistance,
        alongAnchorM: CLLocationDistance? = nil
    ) -> [CLLocationCoordinate2D] {
        let points = routePoints(of: route, relativeTo: location)
        guard points.count >= 2,
              let fix = project(points, alongAnchorM: alongAnchorM) else {
            return route.coordinates
        }

        var result: [CLLocationCoordinate2D] = [
            coordinate(from: location, east: fix.projection.x, north: fix.projection.y)
        ]
        var remaining = aheadM
        var previous = fix.projection

        for index in (fix.segmentIndex + 1)..<points.count {
            let point = points[index]
            let length = simd_distance(previous, point)
            if length >= remaining {
                let ratio = length > 0 ? remaining / length : 0
                let clipped = previous + (point - previous) * ratio
                result.append(
                    coordinate(from: location, east: clipped.x, north: clipped.y)
                )
                return result
            }
            remaining -= length
            result.append(route.coordinates[index])
            previous = point
        }
        return result
    }

    /// Fügt Zwischen-Wegpunkte ein, sodass zwei aufeinanderfolgende Punkte
    /// höchstens `maxSpacingM` auseinanderliegen. ORS/MapKit liefern die Route
    /// nur an Knick- und Kreuzungspunkten; für den AR-Bodenpfad (Teppich +
    /// Richtungs-Chevrons) braucht es dichtere, aus GPS abgeleitete
    /// Stützpunkte, damit der Pfad der Gasse folgt und die Chevrons in
    /// gleichmässigem Abstand entlang der ganzen Strecke sitzen, statt lange
    /// gerade Segmente zu überspringen. Über kurze Distanzen genügt die
    /// lineare Interpolation in Breiten-/Längengrad.
    static func densify(
        _ coordinates: [CLLocationCoordinate2D],
        maxSpacingM: CLLocationDistance
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count >= 2, maxSpacingM > 0 else { return coordinates }

        var result: [CLLocationCoordinate2D] = [coordinates[0]]
        for i in 1..<coordinates.count {
            let a = coordinates[i - 1]
            let b = coordinates[i]
            let length = simd_length(metersEastNorth(of: b, relativeTo: a))
            if length > maxSpacingM {
                let steps = Int((length / maxSpacingM).rounded(.up))
                for s in 1..<steps {
                    let t = Double(s) / Double(steps)
                    result.append(
                        CLLocationCoordinate2D(
                            latitude: a.latitude + (b.latitude - a.latitude) * t,
                            longitude: a.longitude + (b.longitude - a.longitude) * t
                        )
                    )
                }
            }
            result.append(b)
        }
        return result
    }

    /// Winkel (Grad), ab dem ein Knick als "leicht links/rechts" gilt.
    private static let slightTurnThresholdDeg = 25.0
    /// Winkel (Grad), ab dem ein Knick als volles Abbiegen gilt.
    private static let turnThresholdDeg = 50.0
    /// Segmente kürzer als das gelten als GPS-/Geometrie-Rauschen.
    private static let minSegmentLengthM = 0.5
    /// Winkel (Grad), ab dem die Blickrichtung als "quer zur Route" gilt und
    /// zuerst eine Ausrichtung zur Route angesagt wird (statt des nächsten
    /// Routenknicks). Bewusst grösser als der Slight-Turn-Schwellwert, damit
    /// nur klare Fehlausrichtungen (quer/rückwärts) die Knick-Ansage überschreiben.
    private static let reorientThresholdDeg = 45.0
    /// Winkel (Grad), ab dem die Ausrichtung als volles Abbiegen (statt "leicht
    /// … halten") angesagt wird. Bewusst hoch: Eine normale Kurskorrektur zur
    /// Route ist eine sanfte "halten"-Ansage; erst eine annähernde Kehrtwende
    /// wird zum "abbiegen".
    private static let reorientTurnThresholdDeg = 120.0
    /// Winkel (Grad), ab dem die Blickrichtung als (annähernd) entgegengesetzt
    /// zur Route gilt und ein "Umdrehen" statt eines seitlichen Abbiegens
    /// angesagt wird. Nahe 180° liegt das Ziel klar hinter einem, dann ist die
    /// Seite (links/rechts) uneindeutig – die eindeutige Ansage ist "umdrehen".
    private static let reorientUTurnThresholdDeg = 150.0

    /// Bestimmt das nächste Manöver auf der Route.
    ///
    /// Ist `heading` (aktuelle Blickrichtung) bekannt und weicht sie stark von
    /// der Routenrichtung ab, wird zuerst eine EGOZENTRISCHE Ausrichtung zur
    /// Route angesagt ("Jetzt links/rechts") – relativ dazu, wohin man gerade
    /// schaut. Ohne diese Korrektur käme die Anweisung nur aus der Routen-
    /// Geometrie und stimmte nicht mit der Blickrichtung überein (z. B. Route
    /// nach Osten, Blick nach Süden ⇒ Osten ist links, nicht rechts).
    ///
    /// Ist man grob zur Route ausgerichtet (oder `heading` unbekannt),
    /// projiziert die Funktion den Standort auf das nächstgelegene Segment und
    /// läuft die Polyline vorwärts bis zum ersten signifikanten Richtungsknick.
    /// Kein Knick mehr → geradeaus bis zum Ziel (distanceM = Restweg).
    static func nextManeuver(
        of route: ActiveRoute,
        at location: CLLocation,
        heading: CLLocationDirection? = nil,
        alongAnchorM: CLLocationDistance? = nil
    ) -> RouteManeuver? {
        let points = routePoints(of: route, relativeTo: location.coordinate)
        guard let fix = project(points, alongAnchorM: alongAnchorM) else { return nil }

        // Blickrichtung quer zur Route → zuerst zur Route hin ausrichten.
        // Bewusst als sanfte "leicht … halten"-Ansage (die Route knickt ja nur
        // ab, es ist kein echtes Abbiegen); erst eine annähernde Kehrtwende
        // wird zum "abbiegen", und bei (annähernd) entgegengesetzter
        // Blickrichtung zum "umdrehen". Die Routenrichtung kommt aus DEMSELBEN
        // Fusspunkt wie der Rest der Ansage – sonst könnte die Ausrichtung auf
        // einem anderen Routenast gemessen werden als der nächste Knick.
        if let heading, let routeBearing = travelBearing(points: points, from: fix) {
            let reorient = normalizedSignedDegrees(routeBearing - heading)
            if abs(reorient) >= reorientThresholdDeg {
                // Kompasskurs im Uhrzeigersinn: positiv = Route rechts der
                // Blickrichtung ⇒ nach rechts halten, negativ ⇒ nach links.
                // Nahe 180° liegt die Route hinter einem ⇒ umdrehen (die Seite
                // ist dann uneindeutig).
                let direction: ManeuverDirection
                if abs(reorient) >= reorientUTurnThresholdDeg {
                    direction = .turnAround
                } else if abs(reorient) >= reorientTurnThresholdDeg {
                    direction = reorient > 0 ? .right : .left
                } else {
                    direction = reorient > 0 ? .slightRight : .slightLeft
                }
                return RouteManeuver(direction: direction, distanceM: 0)
            }
        }

        let bestIndex = fix.segmentIndex
        let bestProjection = fix.projection

        // Vorwärts laufen und den ersten signifikanten Knick suchen.
        var traveled = simd_distance(bestProjection, points[bestIndex + 1])
        var incoming = points[bestIndex + 1] - bestProjection
        if simd_length(incoming) < minSegmentLengthM {
            incoming = points[bestIndex + 1] - points[bestIndex]
        }

        for j in (bestIndex + 1)..<(points.count - 1) {
            let outgoing = points[j + 1] - points[j]
            let segmentLength = simd_length(outgoing)
            guard segmentLength >= minSegmentLengthM, simd_length(incoming) >= minSegmentLengthM else {
                traveled += segmentLength
                continue
            }

            let angle = signedAngleDegrees(from: incoming, to: outgoing)
            if abs(angle) >= slightTurnThresholdDeg {
                let direction: ManeuverDirection
                if abs(angle) >= turnThresholdDeg {
                    direction = angle > 0 ? .left : .right
                } else {
                    direction = angle > 0 ? .slightLeft : .slightRight
                }
                return RouteManeuver(direction: direction, distanceM: traveled)
            }

            incoming = outgoing
            traveled += segmentLength
        }

        return RouteManeuver(direction: .straight, distanceM: traveled)
    }

    /// Kürzeste Distanz (Meter) von einer Koordinate zum Routen-Polyline.
    /// Für die Korridor-Filterung der Barrieren entlang der aktiven Route.
    static func distance(from coordinate: CLLocationCoordinate2D, to route: ActiveRoute) -> CLLocationDistance {
        let coords = route.coordinates
        guard coords.count >= 2 else {
            let target = coords.first ?? route.destinationCoordinate
            return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
        }

        // Lokales Ost/Nord-Meter-Koordinatensystem um die Koordinate:
        // sie selbst liegt im Ursprung (0,0).
        let points = routePoints(of: route, relativeTo: coordinate)
        guard let fix = project(points) else { return .greatestFiniteMagnitude }
        return fix.offsetM
    }

    /// Weglänge (Meter) vom Routen-Start bis zur Projektion der Koordinate
    /// auf das nächstgelegene Routensegment. Für die Reihenfolge und die
    /// "nach X m"-Angabe der Barrieren in der Routen-Liste.
    static func distanceAlongRoute(
        to coordinate: CLLocationCoordinate2D,
        on route: ActiveRoute
    ) -> CLLocationDistance {
        // Lokales Ost/Nord-Meter-Koordinatensystem um die Koordinate:
        // sie selbst liegt im Ursprung (0,0).
        let points = routePoints(of: route, relativeTo: coordinate)
        guard let fix = project(points) else { return 0 }
        return fix.alongM
    }

    // MARK: - Karten-Ausrichtung

    /// Ab dieser Weglänge gilt ein Punkt als "weit genug voraus", um die
    /// Anfangsrichtung der Route stabil zu bestimmen (kurze GPS-/Geometrie-
    /// Segmente am Start verfälschen die Richtung sonst).
    private static let initialBearingLookaheadM = 20.0

    /// Anfängliche Fahrtrichtung der Route als Kompasskurs (Grad, 0 = Nord,
    /// im Uhrzeigersinn). Damit lässt sich die Karte beim Anzeigen der Route
    /// so drehen, dass die Fahrtrichtung nach oben zeigt – man sieht sofort,
    /// wohin man fahren muss. Gemessen über die ersten `initialBearingLookaheadM`
    /// Meter; reicht der Vorlauf nicht, zählt die Luftlinie zum Ziel.
    static func initialBearingDegrees(of route: ActiveRoute) -> CLLocationDirection {
        guard let start = route.coordinates.first else { return 0 }
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)

        let reference = route.coordinates.dropFirst().first { candidate in
            startLocation.distance(
                from: CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
            ) >= initialBearingLookaheadM
        } ?? route.destinationCoordinate

        return bearingDegrees(from: start, to: reference)
    }

    /// Vorausschau (Meter), über die die Fahrtrichtung am aktuellen Standort
    /// gemittelt wird – glättet die Kartendrehung über kurze Segmente/Knicke.
    private static let travelBearingLookaheadM = 18.0

    /// Fahrtrichtung der Route am aktuellen Standort als Kompasskurs (Grad,
    /// 0 = Nord). Projiziert den Standort auf das nächstgelegene Segment und
    /// nimmt die Richtung `travelBearingLookaheadM` Meter voraus. Damit dreht
    /// sich die Karte während der Navigation mit dem Routenverlauf mit – nach
    /// rechts, wenn die Route rechts abbiegt, nach links, wenn sie links geht.
    /// nil, wenn die Route zu kurz ist oder der Standort schon am Ziel liegt.
    static func travelBearingDegrees(
        of route: ActiveRoute,
        at location: CLLocation,
        alongAnchorM: CLLocationDistance? = nil
    ) -> CLLocationDirection? {
        let points = routePoints(of: route, relativeTo: location.coordinate)
        guard let fix = project(points, alongAnchorM: alongAnchorM) else { return nil }
        return travelBearing(points: points, from: fix)
    }

    /// Fahrtrichtung ab einem bereits bestimmten Fusspunkt: läuft die Polyline
    /// vom Fusspunkt aus `travelBearingLookaheadM` Meter vorwärts (oder bis zum
    /// Ziel) und misst den Kompasskurs dorthin.
    private static func travelBearing(
        points: [SIMD2<Double>],
        from fix: ProjectedFix
    ) -> CLLocationDirection? {
        guard points.count >= 2 else { return nil }

        var remaining = travelBearingLookaheadM
        var reference = points[points.count - 1]
        var segmentStart = fix.projection
        for j in (fix.segmentIndex + 1)..<points.count {
            let segmentEnd = points[j]
            let segmentLength = simd_distance(segmentStart, segmentEnd)
            if segmentLength >= remaining {
                reference = segmentStart + (segmentEnd - segmentStart) / segmentLength * remaining
                break
            }
            remaining -= segmentLength
            segmentStart = segmentEnd
        }

        // Richtungsvektor Projektion → Vorausschau-Punkt (x = Ost, y = Nord).
        let vector = reference - fix.projection
        guard simd_length(vector) > 0.1 else { return nil }
        let bearing = atan2(vector.x, vector.y) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Kompasskurs (Grad, 0 = Nord, im Uhrzeigersinn) von `start` nach `end`.
    static func bearingDegrees(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> CLLocationDirection {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLon = (end.longitude - start.longitude) * .pi / 180

        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    // MARK: - Helpers

    private static func remainingTime(for remainingDistance: Double, on route: ActiveRoute) -> TimeInterval {
        guard route.totalDistanceM > 0 else { return 0 }
        return route.expectedTravelTimeS * min(1, remainingDistance / route.totalDistanceM)
    }

    /// Vorzeichenbehafteter Winkel zwischen zwei Richtungsvektoren im
    /// Ost/Nord-System: positiv = Linkskurve (gegen den Uhrzeigersinn).
    private static func signedAngleDegrees(from a: SIMD2<Double>, to b: SIMD2<Double>) -> Double {
        let cross = a.x * b.y - a.y * b.x
        let dot = simd_dot(a, b)
        return atan2(cross, dot) * 180 / .pi
    }

    /// Normiert einen Winkel (Grad) auf (−180, 180]. Für die egozentrische
    /// Ausrichtung: positiv = im Uhrzeigersinn (rechts), negativ = links.
    private static func normalizedSignedDegrees(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value <= -180 { value += 360 }
        if value > 180 { value -= 360 }
        return value
    }

    /// Flach-Erde-Näherung wie in ARGeoMapper: x = Ost-Meter, y = Nord-Meter.
    private static func metersEastNorth(
        of target: CLLocationCoordinate2D,
        relativeTo origin: CLLocationCoordinate2D
    ) -> SIMD2<Double> {
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(origin.latitude * .pi / 180)
        return SIMD2(
            (target.longitude - origin.longitude) * metersPerDegreeLongitude,
            (target.latitude - origin.latitude) * metersPerDegreeLatitude
        )
    }

    /// Umkehrung von `metersEastNorth`: Koordinate aus Ost-/Nord-Metern
    /// relativ zu `origin` (Flach-Erde-Näherung).
    private static func coordinate(
        from origin: CLLocationCoordinate2D,
        east: Double,
        north: Double
    ) -> CLLocationCoordinate2D {
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(origin.latitude * .pi / 180)
        return CLLocationCoordinate2D(
            latitude: origin.latitude + north / metersPerDegreeLatitude,
            longitude: origin.longitude + east / metersPerDegreeLongitude
        )
    }
}

extension MKPolyline {
    /// Alle Koordinaten des Polylines als Array.
    func coordinateList() -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: pointCount
        )
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

// MARK: - OpenRouteService DTOs
// https://openrouteservice.org/dev/#/api-docs/v2/directions/{profile}/geojson/post

/// Request-Body für POST /v2/directions/wheelchair/geojson.
/// Koordinaten in GeoJSON-Reihenfolge: [Längengrad, Breitengrad].
/// Bewusst nicht `private`, damit sich in den Tests nachprüfen lässt, dass die
/// Anfrage exakt die von ORS dokumentierten Parameter und Werte enthält.
struct ORSDirectionsRequest: Encodable {
    let coordinates: [[Double]]
    let options: Options

    struct Options: Encodable {
        let profileParams: ProfileParams
        /// GeoJSON-Sperrflächen um zu umgehende Barrieren (nil = keine).
        let avoidPolygons: AvoidPolygons?
        /// Wegearten, die die Route nicht benutzen darf.
        ///
        /// Fähren sind in OSM ganz normale Routen-Ways und für ORS
        /// grundsätzlich befahrbar – in Zürich ist das das Limmatschiff.
        /// Ohne diese Sperre schickt das Routing für ein Ziel auf der anderen
        /// Uferseite gern quer über den Fluss und wieder zurück (im Feldtest
        /// als kilometerlange gerade Linie über die Limmat sichtbar). Für die
        /// Mikronavigation in der Altstadt ist eine Schifffahrt nie die
        /// gemeinte Antwort.
        let avoidFeatures: [String]

        enum CodingKeys: String, CodingKey {
            case profileParams = "profile_params"
            case avoidPolygons = "avoid_polygons"
            case avoidFeatures = "avoid_features"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(profileParams, forKey: .profileParams)
            try container.encodeIfPresent(avoidPolygons, forKey: .avoidPolygons)
            if !avoidFeatures.isEmpty {
                try container.encode(avoidFeatures, forKey: .avoidFeatures)
            }
        }
    }

    /// Wegearten, die für die Rollstuhl-Mikronavigation ausgeschlossen sind.
    /// Genau die Kombination, die die ORS-Doku im Beispiel für das
    /// Rollstuhlprofil zeigt.
    static let excludedFeatures = ["ferries", "steps"]

    /// GeoJSON-MultiPolygon: ein kleines Achteck (~15 m Radius) um jede zu
    /// umgehende Barriere, damit ORS die Stelle nicht auf der Route hat.
    struct AvoidPolygons: Encodable {
        let type = "MultiPolygon"
        /// [[Ring: [[lng, lat], …, erster Punkt wiederholt]]] je Barriere.
        let coordinates: [[[[Double]]]]

        /// Radius der Sperrfläche um eine Barriere in Metern.
        static let clearanceRadiusM = 15.0

        init?(around centers: [CLLocationCoordinate2D]) {
            guard !centers.isEmpty else { return nil }
            coordinates = centers.map { [Self.octagonRing(around: $0)] }
        }

        /// Geschlossener Achteck-Ring um die Koordinate (GeoJSON-Reihenfolge
        /// [Längengrad, Breitengrad], erster Punkt am Ende wiederholt).
        private static func octagonRing(around center: CLLocationCoordinate2D) -> [[Double]] {
            let metersPerDegreeLatitude = 111_320.0
            let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(center.latitude * .pi / 180)

            var ring: [[Double]] = (0..<8).map { i in
                let angle = Double(i) / 8 * 2 * .pi
                return [
                    center.longitude + clearanceRadiusM * cos(angle) / metersPerDegreeLongitude,
                    center.latitude + clearanceRadiusM * sin(angle) / metersPerDegreeLatitude,
                ]
            }
            ring.append(ring[0])
            return ring
        }
    }

    struct ProfileParams: Encodable {
        let restrictions: Restrictions
    }

    /// Vorgaben an das ORS-Rollstuhlprofil. Jede entspricht einem der im
    /// OSM-Wiki (Wheelchair routing) beschriebenen Tags:
    /// incline, sloped_curb/kerb:height, width, surface, smoothness, tracktype.
    struct Restrictions: Encodable {
        /// Maximale Steigung in Prozent (OSM `incline`).
        let maximumIncline: Int
        /// Maximale Bordsteinhöhe in Metern (OSM `sloped_curb`, `kerb:height`).
        let maximumSlopedKerb: Double
        /// Minimale Wegbreite in Metern (OSM `width`). nil = keine Vorgabe.
        let minimumWidth: Double?
        /// Schlechteste noch akzeptierte Oberfläche (OSM `surface`).
        let surfaceType: String
        /// Schlechteste noch akzeptierte Ebenheit (OSM `smoothness`).
        let smoothnessType: String
        /// Schlechteste noch akzeptierte Wegequalität (OSM `tracktype`).
        let trackType: String

        enum CodingKeys: String, CodingKey {
            case maximumIncline = "maximum_incline"
            case maximumSlopedKerb = "maximum_sloped_kerb"
            case minimumWidth = "minimum_width"
            case surfaceType = "surface_type"
            case smoothnessType = "smoothness_type"
            case trackType = "track_type"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(maximumIncline, forKey: .maximumIncline)
            try container.encode(maximumSlopedKerb, forKey: .maximumSlopedKerb)
            try container.encodeIfPresent(minimumWidth, forKey: .minimumWidth)
            try container.encode(surfaceType, forKey: .surfaceType)
            try container.encode(smoothnessType, forKey: .smoothnessType)
            try container.encode(trackType, forKey: .trackType)
        }

        /// Werte, die ORS für `maximum_incline` akzeptiert (Prozent).
        /// Die API kennt nur diese Stufen – ein "krummer" Wert wie 9 % ist
        /// nicht vorgesehen und würde die Anfrage gefährden.
        static let allowedInclines = [3, 6, 10, 15]
        /// Werte, die ORS für `maximum_sloped_kerb` akzeptiert (Meter).
        static let allowedSlopedKerbs = [0.03, 0.06, 0.1]

        /// Grösster erlaubter Wert, der das persönliche Limit NICHT
        /// überschreitet – lieber etwas strenger routen als über eine Kante,
        /// die zu hoch ist. Liegt das Limit unter der kleinsten Stufe, bleibt
        /// diese (feiner kann ORS nicht).
        private static func snappedDown<T: Comparable>(_ value: T, to allowed: [T]) -> T {
            allowed.last { $0 <= value } ?? allowed[0]
        }

        /// Vorgaben aus dem Profil. `relaxed` weitet sie auf die
        /// ORS-Standardwerte (die den Norm-Grenzwerten entsprechen, siehe
        /// AccessibilityStandard) und lässt die Breitenvorgabe ganz weg – in
        /// der Altstadt ist `width` an den wenigsten Gassen erfasst, eine
        /// strikte Mindestbreite schliesst deshalb schnell das halbe Wegnetz
        /// aus.
        init(profile: UserProfile, relaxed: Bool = false) {
            // Oberflächen-Toleranz inkl. Tagesform (Nässe verschiebt sie eine
            // Stufe Richtung "nur glatt") – dieselbe Grundlage wie die
            // Barrieren-Bewertung.
            let tolerance = profile.effectiveSurfaceTolerance

            let personalIncline = Self.snappedDown(
                Int(profile.effectiveMaxIncline.rounded(.down)),
                to: Self.allowedInclines
            )
            let personalKerb = Self.snappedDown(
                profile.effectiveMaxCurb / 100, // cm → m
                to: Self.allowedSlopedKerbs
            )

            if relaxed {
                // Nie strenger als die eigenen Werte, aber mindestens die
                // Norm-/ORS-Standardstufe.
                maximumIncline = max(personalIncline, 6)
                maximumSlopedKerb = max(personalKerb, 0.06)
                minimumWidth = nil
                surfaceType = "cobblestone"
                smoothnessType = "very_bad"
                trackType = "grade3"
            } else {
                maximumIncline = personalIncline
                maximumSlopedKerb = personalKerb
                minimumWidth = Double(profile.effectiveWidthNeeded) / 100 // cm → m
                surfaceType = Self.surfaceType(for: tolerance)
                smoothnessType = Self.smoothnessType(for: tolerance)
                trackType = Self.trackType(for: tolerance)
            }
        }

        private static func surfaceType(for tolerance: SurfaceTolerance) -> String {
            switch tolerance {
            case .smoothOnly: return "paved"
            case .fineCobble: return "cobblestone:flattened"
            case .almostAll: return "cobblestone"
            }
        }

        /// OSM `smoothness`: Das Wiki führt für Rollstühle "intermediate" als
        /// gerade noch nutzbar (Citybike/Rollstuhl/Kinderwagen), "bad" nur für
        /// robuste Bereifung.
        private static func smoothnessType(for tolerance: SurfaceTolerance) -> String {
            switch tolerance {
            case .smoothOnly: return "good"
            case .fineCobble: return "intermediate"
            case .almostAll: return "bad"
            }
        }

        /// OSM `tracktype`: grade1 = befestigt/stark verdichtet,
        /// grade2 = Kies oder dicht gepackter Sand (Wiki-Tabelle).
        private static func trackType(for tolerance: SurfaceTolerance) -> String {
            switch tolerance {
            case .smoothOnly, .fineCobble: return "grade1"
            case .almostAll: return "grade2"
            }
        }
    }
}

/// GeoJSON-Antwort von ORS: Route als LineString plus Distanz/Dauer-Summary.
private struct ORSDirectionsResponse: Decodable {
    let features: [Feature]

    struct Feature: Decodable {
        let geometry: Geometry
        let properties: Properties
    }

    struct Geometry: Decodable {
        /// LineString-Koordinaten: [[Längengrad, Breitengrad], …]
        let coordinates: [[Double]]
    }

    struct Properties: Decodable {
        let summary: Summary
        /// Abschnitte mit Turn-by-turn-Schritten (ORS liefert sie standardmässig,
        /// `instructions=true`). Optional, damit das Fehlen nicht die ganze
        /// Route-Dekodierung scheitern lässt.
        let segments: [Segment]?
    }

    struct Summary: Decodable {
        /// Gesamtdistanz in Metern.
        let distance: Double
        /// Erwartete Dauer in Sekunden.
        let duration: Double
    }

    /// Ein Routenabschnitt (Start → Zwischenziel/Ziel) mit seinen Schritten.
    struct Segment: Decodable {
        let steps: [Step]
    }

    /// Ein einzelner Turn-by-turn-Schritt (Manöver + Weg).
    struct Step: Decodable {
        /// Länge des Schritts in Metern.
        let distance: Double
        /// Dauer des Schritts in Sekunden.
        let duration: Double
        /// ORS-Instruktionstyp (0–13), siehe StepManeuver.fromORSType.
        let type: Int
        /// Strassen-/Wegname ("-" für unbenannte Wege).
        let name: String?
        /// Start-/Endindex des Schritts in der Routengeometrie.
        let wayPoints: [Int]

        enum CodingKeys: String, CodingKey {
            case distance, duration, type, name
            case wayPoints = "way_points"
        }
    }
}