// RouteService.swift
// ARMikronav
//
// Berechnet rollstuhlgerechte Routen via OpenRouteService (Profil
// "wheelchair", mit den persönlichen Limits aus dem UserProfile) und
// liefert den Fortschritt (Restdistanz/Restzeit) entlang einer aktiven
// Route. Findet ORS keine rollstuhlgerechte Route (oder ist kein API-Key
// konfiguriert), fällt der Service auf die MapKit-Fussgängerroute zurück –
// gekennzeichnet über RouteKind, damit die UI den Fallback ausweist.
// Die Route wird als Wegpunkt-Liste gehalten, damit Karte (MapPolyline)
// und AR-Rendering (ARRouteRenderer) dieselbe Geometrie verwenden.

import Foundation
import MapKit
import CoreLocation
import simd

/// Wie die Route berechnet wurde.
enum RouteKind: Equatable {
    /// Rollstuhlgerechte Route (OpenRouteService, Profil-Limits berücksichtigt).
    case wheelchair
    /// MapKit-Fussgängerroute als Fallback – Barrieren nicht berücksichtigt.
    case walkingFallback
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

/// Richtung des nächsten Manövers entlang der Route (aus der Polyline-
/// Geometrie abgeleitet). Positiver Winkel = Linkskurve.
enum ManeuverDirection: Equatable {
    case straight
    case slightLeft
    case slightRight
    case left
    case right

    var symbolName: String {
        switch self {
        case .straight:    return "arrow.up"
        case .slightLeft:  return "arrow.up.left"
        case .slightRight: return "arrow.up.right"
        case .left:        return "arrow.turn.up.left"
        case .right:       return "arrow.turn.up.right"
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

    /// Berechnet die Route zum Ziel: zuerst rollstuhlgerecht via
    /// OpenRouteService mit den Limits aus dem Profil. Schlägt das fehl
    /// (kein API-Key, Netzfehler, keine rollstuhlgerechte Route), kommt
    /// die MapKit-Fussgängerroute als gekennzeichneter Fallback.
    static func route(
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
                profile: profile
            )
        } catch {
            return try await walkingRoute(
                from: start,
                to: destination,
                destinationName: destinationName
            )
        }
    }

    // MARK: - Rollstuhl-Route (OpenRouteService)

    /// Fragt das ORS-Profil "wheelchair" an. Die Restriktionen kommen aus
    /// dem UserProfile: max. Steigung, max. Bordsteinhöhe, benötigte Breite
    /// (inkl. Begleitungs-Bonus via effective*-Werte) und Oberflächentoleranz.
    /// `avoiding` sind Barrieren-Koordinaten, die die Route umgehen soll
    /// (Tagesform: z. B. Steigung, die bei Hitze nicht machbar ist) – sie
    /// werden als avoid_polygons an ORS übergeben.
    static func wheelchairRoute(
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        profile: UserProfile,
        avoiding: [CLLocationCoordinate2D] = []
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
                profileParams: .init(restrictions: .init(profile: profile)),
                avoidPolygons: ORSDirectionsRequest.AvoidPolygons(around: avoiding)
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

        return ActiveRoute(
            destinationName: destinationName,
            destinationCoordinate: destination,
            coordinates: coordinates,
            totalDistanceM: feature.properties.summary.distance,
            expectedTravelTimeS: feature.properties.summary.duration,
            kind: .wheelchair,
            steps: orsSteps(from: feature.properties.segments, coordinates: coordinates)
        )
    }

    /// Baut die Turn-by-turn-Schritte aus den ORS-Segmenten. Jeder Schritt
    /// referenziert über `way_points` seinen Startpunkt in der Routengeometrie.
    private static func orsSteps(
        from segments: [ORSDirectionsResponse.Segment]?,
        coordinates: [CLLocationCoordinate2D]
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
                        durationS: step.duration,
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
    /// Barrieren-Berücksichtigung).
    static func walkingRoute(
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String
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
            expectedTravelTimeS: route.expectedTravelTime,
            kind: .walkingFallback,
            steps: walkingSteps(from: route)
        )
    }

    /// Baut die Turn-by-turn-Schritte aus einer MapKit-Route. MKRoute liefert
    /// nur Anweisungstext (keine strukturierten Manöver) – das Manöver-Icon
    /// wird best-effort aus dem Text abgeleitet, der Text selbst angezeigt.
    /// Schritte ohne Anweisung (ausser dem Start) werden übersprungen.
    private static func walkingSteps(from route: MKRoute) -> [RouteStep] {
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
                    coordinate: coordinate
                )
            )
        }
        return steps
    }

    /// Projiziert den Standort auf das nächstgelegene Routensegment und
    /// summiert die verbleibenden Segmentlängen. Restzeit anteilig zur
    /// erwarteten Gesamtzeit.
    static func progress(of route: ActiveRoute, at location: CLLocation) -> RouteProgress {
        let coords = route.coordinates
        guard coords.count >= 2 else {
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

        // Lokales Ost/Nord-Meter-Koordinatensystem um den aktuellen Standort:
        // der Standort selbst liegt im Ursprung (0,0).
        let points = coords.map { metersEastNorth(of: $0, relativeTo: location.coordinate) }

        // suffix[i] = Weglänge von Punkt i bis zum Ziel.
        var suffix = [Double](repeating: 0, count: points.count)
        for i in stride(from: points.count - 2, through: 0, by: -1) {
            suffix[i] = suffix[i + 1] + simd_distance(points[i], points[i + 1])
        }

        var bestDistanceToPath = Double.greatestFiniteMagnitude
        var bestRemaining = suffix[0]

        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let ab = b - a
            let lengthSquared = simd_length_squared(ab)
            let t = lengthSquared > 0 ? min(1, max(0, simd_dot(-a, ab) / lengthSquared)) : 0
            let projected = a + t * ab
            let distanceToPath = simd_length(projected)
            if distanceToPath < bestDistanceToPath {
                bestDistanceToPath = distanceToPath
                bestRemaining = simd_distance(projected, b) + suffix[i + 1]
            }
        }

        return RouteProgress(
            remainingDistanceM: bestRemaining,
            remainingTimeS: remainingTime(for: bestRemaining, on: route)
        )
    }

    /// Projiziert den Standort auf das nächstgelegene Routensegment und gibt
    /// den Fusspunkt (auf der violetten Linie) samt seitlichem Abstand zurück.
    /// Damit lässt sich der Standortpunkt auf der Karte auf die Route
    /// "einrasten", solange man nah genug an ihr ist – so springt er nicht mehr
    /// neben der Linie herum (GPS-Rauschen und Mehrwegempfang in den engen,
    /// hohen Altstadt-Gassen). Der Aufrufer entscheidet über `offsetM`, ob
    /// eingerastet oder der Rohstandort gezeigt wird.
    static func snappedLocation(on route: ActiveRoute, at location: CLLocation) -> RouteSnap {
        let coords = route.coordinates
        let origin = location.coordinate
        guard coords.count >= 2 else {
            return RouteSnap(coordinate: origin, offsetM: 0)
        }

        // Lokales Ost/Nord-Meter-Koordinatensystem um den Standort (0,0).
        let points = coords.map { metersEastNorth(of: $0, relativeTo: origin) }

        var bestOffset = Double.greatestFiniteMagnitude
        var bestProjection = points[0]
        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let ab = b - a
            let lengthSquared = simd_length_squared(ab)
            let t = lengthSquared > 0 ? min(1, max(0, simd_dot(-a, ab) / lengthSquared)) : 0
            let projected = a + t * ab
            let offset = simd_length(projected)
            if offset < bestOffset {
                bestOffset = offset
                bestProjection = projected
            }
        }

        // Fusspunkt (Meter Ost/Nord relativ zum Standort) zurück in Koordinaten.
        return RouteSnap(
            coordinate: coordinate(from: origin, east: bestProjection.x, north: bestProjection.y),
            offsetM: bestOffset
        )
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
        heading: CLLocationDirection? = nil
    ) -> RouteManeuver? {
        let coords = route.coordinates
        guard coords.count >= 2 else { return nil }

        // Blickrichtung quer zur Route → zuerst zur Route hin ausrichten.
        // Bewusst als sanfte "leicht … halten"-Ansage (die Route knickt ja nur
        // ab, es ist kein echtes Abbiegen); erst eine annähernde Kehrtwende
        // wird zum "abbiegen".
        if let heading, let routeBearing = travelBearingDegrees(of: route, at: location) {
            let reorient = normalizedSignedDegrees(routeBearing - heading)
            if abs(reorient) >= reorientThresholdDeg {
                // Kompasskurs im Uhrzeigersinn: positiv = Route rechts der
                // Blickrichtung ⇒ nach rechts halten, negativ ⇒ nach links.
                let direction: ManeuverDirection
                if abs(reorient) >= reorientTurnThresholdDeg {
                    direction = reorient > 0 ? .right : .left
                } else {
                    direction = reorient > 0 ? .slightRight : .slightLeft
                }
                return RouteManeuver(direction: direction, distanceM: 0)
            }
        }

        // Lokales Ost/Nord-Meter-Koordinatensystem um den Standort (0,0).
        let points = coords.map { metersEastNorth(of: $0, relativeTo: location.coordinate) }

        // Nächstgelegenes Segment + Projektionspunkt (wie in progress).
        var bestDistanceToPath = Double.greatestFiniteMagnitude
        var bestIndex = 0
        var bestProjection = points[0]

        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let ab = b - a
            let lengthSquared = simd_length_squared(ab)
            let t = lengthSquared > 0 ? min(1, max(0, simd_dot(-a, ab) / lengthSquared)) : 0
            let projected = a + t * ab
            let distanceToPath = simd_length(projected)
            if distanceToPath < bestDistanceToPath {
                bestDistanceToPath = distanceToPath
                bestIndex = i
                bestProjection = projected
            }
        }

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
        let points = coords.map { metersEastNorth(of: $0, relativeTo: coordinate) }

        var best = Double.greatestFiniteMagnitude
        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let ab = b - a
            let lengthSquared = simd_length_squared(ab)
            let t = lengthSquared > 0 ? min(1, max(0, simd_dot(-a, ab) / lengthSquared)) : 0
            best = min(best, simd_length(a + t * ab))
        }
        return best
    }

    /// Weglänge (Meter) vom Routen-Start bis zur Projektion der Koordinate
    /// auf das nächstgelegene Routensegment. Für die Reihenfolge und die
    /// "nach X m"-Angabe der Barrieren in der Routen-Liste.
    static func distanceAlongRoute(
        to coordinate: CLLocationCoordinate2D,
        on route: ActiveRoute
    ) -> CLLocationDistance {
        let coords = route.coordinates
        guard coords.count >= 2 else { return 0 }

        // Lokales Ost/Nord-Meter-Koordinatensystem um die Koordinate:
        // sie selbst liegt im Ursprung (0,0).
        let points = coords.map { metersEastNorth(of: $0, relativeTo: coordinate) }

        // prefix[i] = Weglänge vom Start bis Punkt i.
        var prefix = [Double](repeating: 0, count: points.count)
        for i in 1..<points.count {
            prefix[i] = prefix[i - 1] + simd_distance(points[i - 1], points[i])
        }

        var bestDistanceToPath = Double.greatestFiniteMagnitude
        var bestAlong = 0.0

        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let ab = b - a
            let lengthSquared = simd_length_squared(ab)
            let t = lengthSquared > 0 ? min(1, max(0, simd_dot(-a, ab) / lengthSquared)) : 0
            let projected = a + t * ab
            let distanceToPath = simd_length(projected)
            if distanceToPath < bestDistanceToPath {
                bestDistanceToPath = distanceToPath
                bestAlong = prefix[i] + simd_distance(a, projected)
            }
        }
        return bestAlong
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
        at location: CLLocation
    ) -> CLLocationDirection? {
        let coords = route.coordinates
        guard coords.count >= 2 else { return nil }

        // Lokales Ost/Nord-Meter-Koordinatensystem um den Standort (0,0).
        let points = coords.map { metersEastNorth(of: $0, relativeTo: location.coordinate) }

        // Nächstgelegenes Segment + Projektionspunkt (wie in nextManeuver).
        var bestDistanceToPath = Double.greatestFiniteMagnitude
        var bestIndex = 0
        var bestProjection = points[0]
        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let ab = b - a
            let lengthSquared = simd_length_squared(ab)
            let t = lengthSquared > 0 ? min(1, max(0, simd_dot(-a, ab) / lengthSquared)) : 0
            let projected = a + t * ab
            let distanceToPath = simd_length(projected)
            if distanceToPath < bestDistanceToPath {
                bestDistanceToPath = distanceToPath
                bestIndex = i
                bestProjection = projected
            }
        }

        // Vom Projektionspunkt aus die Polyline vorwärts laufen, bis
        // `travelBearingLookaheadM` Meter erreicht sind (oder das Ziel).
        var remaining = travelBearingLookaheadM
        var reference = points[points.count - 1]
        var segmentStart = bestProjection
        for j in (bestIndex + 1)..<points.count {
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
        let vector = reference - bestProjection
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
private struct ORSDirectionsRequest: Encodable {
    let coordinates: [[Double]]
    let options: Options

    struct Options: Encodable {
        let profileParams: ProfileParams
        /// GeoJSON-Sperrflächen um zu umgehende Barrieren (nil = keine).
        let avoidPolygons: AvoidPolygons?

        enum CodingKeys: String, CodingKey {
            case profileParams = "profile_params"
            case avoidPolygons = "avoid_polygons"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(profileParams, forKey: .profileParams)
            try container.encodeIfPresent(avoidPolygons, forKey: .avoidPolygons)
        }
    }

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

    struct Restrictions: Encodable {
        /// Maximale Steigung in Prozent.
        let maximumIncline: Int
        /// Maximale Bordsteinhöhe in Metern.
        let maximumSlopedKerb: Double
        /// Minimale Wegbreite in Metern.
        let minimumWidth: Double
        /// Schlechteste noch akzeptierte Oberfläche (OSM surface=*).
        let surfaceType: String

        enum CodingKeys: String, CodingKey {
            case maximumIncline = "maximum_incline"
            case maximumSlopedKerb = "maximum_sloped_kerb"
            case minimumWidth = "minimum_width"
            case surfaceType = "surface_type"
        }

        init(profile: UserProfile) {
            maximumIncline = Int(profile.effectiveMaxIncline.rounded())
            maximumSlopedKerb = profile.effectiveMaxCurb / 100 // cm → m
            minimumWidth = Double(profile.effectiveWidthNeeded) / 100 // cm → m
            surfaceType = Self.surfaceType(for: profile.surfaceTolerance)
        }

        private static func surfaceType(for tolerance: SurfaceTolerance) -> String {
            switch tolerance {
            case .smoothOnly: return "paved"
            case .fineCobble: return "cobblestone:flattened"
            case .almostAll: return "cobblestone"
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