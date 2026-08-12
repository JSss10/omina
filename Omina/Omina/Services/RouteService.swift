// RouteService.swift
// Omina
//
// Berechnet die Route zum Ziel und liefert den Fortschritt (Restdistanz/
// Restzeit) entlang einer aktiven Route.
//
// Die Standardroute ist die FUSSGÄNGERROUTE (MapKit): Sie folgt dem direkten
// Weg, den man auch selbst nehmen würde. Das OSM-Rollstuhl-Routing
// (OpenRouteService, Profil "wheelchair") ist dafür bewusst nicht mehr im
// Einsatz – in der Zürcher Altstadt sind `width`, `surface` und `incline` an
// den wenigsten Gassen erfasst, wodurch die Profil-Restriktionen halbe
// Wegnetze ausschliessen und die Route im Feldtest wiederholt weiträumige
// Umwege vorschlug, wo der direkte Weg frei war.
//
// Die Rollstuhl-Perspektive steckt stattdessen dort, wo die Daten es hergeben:
// in der personalisierten Barrierenbewertung entlang der Route (BarrierLogic,
// OSMSurfaceRating), in den Warnungen und in der Barrieren-Liste zur Route.
// Das OSM-Routing wird nur noch für die Alternativroute um eine konkrete
// Barriere herum genutzt – dafür braucht es avoid_polygons, das MapKit nicht
// kann.
//
// Fahrzeiten kommen nicht von den Routing-Diensten (die rechnen mit
// Fussgänger-Tempo), sondern aus der eigenen Geschwindigkeit im Profil.
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

enum RouteService {
    enum RouteError: GermanLocalizedError {
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
    /// Verhältnis Routenlänge zu Luftlinie, ab dem eine Route als
    /// unplausibel gilt.
    private static let implausibleDetourFactor = 6.0
    /// Sockel obendrauf, damit normale Umwege auf kurzen Strecken (Hauseingang
    /// auf der anderen Seite, Treppe umfahren) nicht anschlagen.
    private static let implausibleDetourMarginM: CLLocationDistance = 250

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

    /// Berechnet die Route zum Ziel: die Fussgängerroute (MapKit) vom
    /// Standort zum Ziel, mit der eigenen Geschwindigkeit als Fahrzeit.
    ///
    /// Bewusst OHNE das OSM-Rollstuhl-Routing: In der Altstadt sind `width`,
    /// `surface` und `incline` an den wenigsten Gassen erfasst, deshalb
    /// schlossen die Profil-Restriktionen dort ganze Wegnetze aus und die
    /// Route führte im Feldtest wiederholt weiträumig um Ziele herum, die
    /// nebenan lagen. Die Fussgängerroute nimmt den Weg, den man auch selbst
    /// nehmen würde – welche Barrieren darauf liegen und ob sie für das eigene
    /// Profil kritisch sind, bewertet die App entlang der fertigen Route
    /// (siehe MapViewModel.routeBarrierEntries und BarrierLogic).
    ///
    /// Um eine bestimmte Barriere herum gibt es weiterhin eine echte
    /// Rollstuhl-Route über OSM (siehe `wheelchairRoute(avoiding:)`).
    static func route(
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        profile: UserProfile
    ) async throws -> ActiveRoute {
        try await walkingRoute(
            from: start,
            to: destination,
            destinationName: destinationName,
            profile: profile
        )
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
            kind: .wheelchair,
            steps: orsSteps(
                from: feature.properties.segments,
                coordinates: coordinates,
                profile: profile
            )
        )
    }

    /// OSM-Rollstuhl-Route, die die übergebenen Barrieren umgeht: zuerst mit
    /// den eigenen Limits, sonst mit gelockerten Vorgaben. Der einzige Ort, an
    /// dem noch über OSM geroutet wird – nur dieses Profil kennt Sperrflächen
    /// (avoid_polygons); eine Fussgängerroute führte einfach wieder über die
    /// Barriere, die man gerade umgehen will.
    ///
    /// Ergibt der Umweg gemessen an der Luftlinie keinen Sinn mehr (Ziel
    /// nebenan, Route kilometerweit), gilt das als "keine Alternative
    /// gefunden" – dann bleibt die bisherige Route stehen, statt eine
    /// unbrauchbare vorzuschlagen.
    static func wheelchairRoute(
        avoiding barriers: [CLLocationCoordinate2D],
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        profile: UserProfile
    ) async throws -> ActiveRoute {
        let alternative: ActiveRoute
        do {
            alternative = try await wheelchairRoute(
                from: start,
                to: destination,
                destinationName: destinationName,
                profile: profile,
                avoiding: barriers
            )
        } catch {
            alternative = try await wheelchairRoute(
                from: start,
                to: destination,
                destinationName: destinationName,
                profile: profile,
                avoiding: barriers,
                relaxed: true
            )
        }

        let beelineM = CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(
                from: CLLocation(latitude: destination.latitude, longitude: destination.longitude)
            )
        guard !isImplausibleDetour(
            routeDistanceM: alternative.totalDistanceM,
            beelineM: beelineM
        ) else {
            throw RouteError.noRoute
        }
        return alternative
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

        return activeRoute(
            from: route,
            to: destination,
            destinationName: destinationName,
            profile: profile
        )
    }

    /// Alle Wegvarianten, die MapKit zum Ziel kennt – die Auswahlliste im
    /// Routen-Sheet. Kürzeste zuerst; welche davon die wenigsten Barrieren
    /// trägt, bewertet das MapViewModel entlang der fertigen Geometrie.
    static func routeOptions(
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        profile: UserProfile
    ) async throws -> [ActiveRoute] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking
        request.requestsAlternateRoutes = true

        let response = try await MKDirections(request: request).calculate()
        guard !response.routes.isEmpty else { throw RouteError.noRoute }

        return response.routes
            .sorted { $0.distance < $1.distance }
            .map {
                activeRoute(
                    from: $0,
                    to: destination,
                    destinationName: destinationName,
                    profile: profile
                )
            }
    }

    /// MapKit-Route in die App-Route übersetzen (Fahrzeit im eigenen Tempo).
    private static func activeRoute(
        from route: MKRoute,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        profile: UserProfile?
    ) -> ActiveRoute {
        ActiveRoute(
            destinationName: destinationName,
            destinationCoordinate: destination,
            coordinates: route.polyline.coordinateList(),
            totalDistanceM: route.distance,
            expectedTravelTimeS: profile.map {
                travelTime(forMeters: route.distance, profile: $0)
            } ?? route.expectedTravelTime,
            kind: .walking,
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

        // Weglänge bis zum jeweiligen Segmentanfang läuft im selben Durchgang
        // mit; die Gesamtlänge steht am Ende der Schleife fest. (Früher lief
        // dafür ein eigener Vorlauf mit eigenem Array – bei ~20 Auswertungen
        // je Sekunde während der Navigation eine unnötige Allokation.)
        var cumulative = 0.0
        var best: (segmentIndex: Int, projection: SIMD2<Double>, offsetM: Double, alongM: Double)?
        var bestScore = Double.greatestFiniteMagnitude

        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let ab = b - a
            let lengthSquared = simd_length_squared(ab)
            let t = lengthSquared > 0 ? min(1, max(0, simd_dot(-a, ab) / lengthSquared)) : 0
            let projected = a + t * ab
            let offset = simd_length(projected)
            let along = cumulative + simd_distance(a, projected)

            var score = offset
            if let alongAnchorM {
                let behind = (alongAnchorM - anchorBacktrackToleranceM) - along
                let ahead = along - (alongAnchorM + anchorForwardWindowM)
                let outside = max(0, max(behind, ahead))
                score += outside * anchorWindowPenaltyPerM
            }

            if score < bestScore {
                bestScore = score
                best = (segmentIndex: i, projection: projected, offsetM: offset, alongM: along)
            }

            cumulative += lengthSquared.squareRoot()
        }

        guard let best else { return nil }
        let totalLength = cumulative
        return ProjectedFix(
            segmentIndex: best.segmentIndex,
            projection: best.projection,
            offsetM: best.offsetM,
            alongM: best.alongM,
            remainingM: max(0, totalLength - best.alongM)
        )
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

    /// Teilt die Route am Fusspunkt des Standorts in den bereits zurückgelegten
    /// und den noch bevorstehenden Teil.
    ///
    /// Aus dem Feldtest: Die Karte zeichnete immer die ganze Route ab dem
    /// ursprünglichen Startpunkt. Steht man dann irgendwo in der Mitte, sieht
    /// die schon gefahrene Schlaufe aus wie ein Umweg, den man noch vor sich
    /// hat ("zeigt einen Umweg an, obwohl ich einfach links gehen könnte").
    /// Mit der Aufteilung kann die Karte den Rest kräftig und das Zurückgelegte
    /// nur blass zeichnen.
    static func split(
        _ route: ActiveRoute,
        at location: CLLocationCoordinate2D,
        alongAnchorM: CLLocationDistance? = nil
    ) -> (covered: [CLLocationCoordinate2D], remaining: [CLLocationCoordinate2D]) {
        let points = routePoints(of: route, relativeTo: location)
        guard points.count >= 2,
              let fix = project(points, alongAnchorM: alongAnchorM) else {
            return ([], route.coordinates)
        }

        let foot = coordinate(
            from: location,
            east: fix.projection.x,
            north: fix.projection.y
        )
        let covered = Array(route.coordinates[0...fix.segmentIndex]) + [foot]
        let remaining = [foot] + Array(route.coordinates[(fix.segmentIndex + 1)...])
        return (covered, remaining)
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

    // MARK: - Massenauswertung: Barrieren gegen die Route

    /// Die Route einmal in ein lokales Ost/Nord-Meter-System (Ursprung =
    /// Routenstart) umgerechnet, samt aufsummierten Segmentlängen.
    ///
    /// Wozu: `distance(from:to:)` und `distanceAlongRoute(to:on:)` bauen dieses
    /// System bei JEDEM Aufruf neu auf – für eine einzelne Abfrage belanglos,
    /// für die Barrieren entlang der Route jedoch nicht. Dort fiele der Aufbau
    /// einmal je Barriere an, also mehrere hundert Mal je Auswertung. Mit der
    /// vorberechneten Geometrie fällt er genau einmal an.
    struct RoutePath {
        fileprivate let origin: CLLocationCoordinate2D
        fileprivate let points: [SIMD2<Double>]
        /// `cumulative[i]` = Weglänge vom Routenstart bis Punkt i.
        fileprivate let cumulative: [Double]
    }

    /// Rechnet die Route einmal in das lokale Meter-System um.
    static func path(of route: ActiveRoute) -> RoutePath {
        let origin = route.coordinates.first ?? route.destinationCoordinate
        // Route ohne Wegpunkte (kein regulärer Zustand, aber nicht ausgeschlossen):
        // Das Ziel als einziger Punkt hält `offsetAndAlong` auf demselben
        // Rückfall wie `distance(from:to:)` – Luftlinie zum Ziel statt
        // "unendlich weit weg".
        let points = route.coordinates.isEmpty
            ? [SIMD2<Double>(0, 0)]
            : route.coordinates.map { metersEastNorth(of: $0, relativeTo: origin) }
        var cumulative = [Double](repeating: 0, count: points.count)
        if points.count >= 2 {
            for i in 1..<points.count {
                cumulative[i] = cumulative[i - 1] + simd_distance(points[i - 1], points[i])
            }
        }
        return RoutePath(origin: origin, points: points, cumulative: cumulative)
    }

    /// Seitlicher Abstand einer Koordinate zur Route UND Weglänge vom
    /// Routenstart bis zu ihrem Fusspunkt – beides in einem Durchgang, auf der
    /// vorberechneten Geometrie. Wie `project` ohne Anker: es gewinnt das
    /// nächstgelegene Segment.
    static func offsetAndAlong(
        of coordinate: CLLocationCoordinate2D,
        on path: RoutePath
    ) -> (offsetM: CLLocationDistance, alongM: CLLocationDistance) {
        let points = path.points
        guard points.count >= 2 else {
            guard let only = points.first else { return (.greatestFiniteMagnitude, 0) }
            let query = metersEastNorth(of: coordinate, relativeTo: path.origin)
            return (simd_distance(only, query), 0)
        }

        // Der Abfragepunkt wandert in den Ursprung – dieselbe Rechnung wie in
        // `project`, nur ohne die Route je Abfrage neu umzurechnen.
        let query = metersEastNorth(of: coordinate, relativeTo: path.origin)

        var bestOffset = Double.greatestFiniteMagnitude
        var bestAlong = 0.0
        for i in 0..<(points.count - 1) {
            let a = points[i] - query
            let b = points[i + 1] - query
            let ab = b - a
            let lengthSquared = simd_length_squared(ab)
            let t = lengthSquared > 0 ? min(1, max(0, simd_dot(-a, ab) / lengthSquared)) : 0
            let projected = a + t * ab
            let offset = simd_length(projected)
            if offset < bestOffset {
                bestOffset = offset
                bestAlong = path.cumulative[i] + simd_distance(a, projected)
            }
        }
        return (bestOffset, bestAlong)
    }

    /// Kürzeste Distanz (Meter) von einer Koordinate zum Routen-Polyline.
    /// Für Einzelabfragen; für ganze Barrieren-Listen `path(of:)` zusammen mit
    /// `offsetAndAlong(of:on:)` verwenden.
    static func distance(from coordinate: CLLocationCoordinate2D, to route: ActiveRoute) -> CLLocationDistance {
        let coords = route.coordinates
        guard coords.count >= 2 else {
            let target = coords.first ?? route.destinationCoordinate
            return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
        }
        return offsetAndAlong(of: coordinate, on: path(of: route)).offsetM
    }

    /// Weglänge (Meter) vom Routen-Start bis zur Projektion der Koordinate
    /// auf das nächstgelegene Routensegment. Für die Reihenfolge und die
    /// "nach X m"-Angabe der Barrieren in der Routen-Liste.
    static func distanceAlongRoute(
        to coordinate: CLLocationCoordinate2D,
        on route: ActiveRoute
    ) -> CLLocationDistance {
        offsetAndAlong(of: coordinate, on: path(of: route)).alongM
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