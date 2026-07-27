// RouteServiceTests.swift
// ARMikronavTests
//
// Tests für die Fortschritts-Berechnung entlang einer aktiven Route
// (RouteService.progress): Restdistanz, Restzeit und Ankunftserkennung.

import Testing
import CoreLocation
@testable import ARMikronav

struct RouteServiceTests {

    /// Gerade Route ~200 m Richtung Norden (Altstadt Zürich).
    private var straightRoute: ActiveRoute {
        let start = CLLocationCoordinate2D(latitude: 47.3700, longitude: 8.5400)
        let end = CLLocationCoordinate2D(latitude: 47.371797, longitude: 8.5400) // ~200 m nördlich
        return ActiveRoute(
            destinationName: "Test-Café",
            destinationCoordinate: end,
            coordinates: [start, end],
            totalDistanceM: 200,
            expectedTravelTimeS: 180
        )
    }

    @Test func progressAtStartIsFullDistance() {
        let route = straightRoute
        let location = CLLocation(latitude: 47.3700, longitude: 8.5400)

        let progress = RouteService.progress(of: route, at: location)

        #expect(abs(progress.remainingDistanceM - 200) < 5)
        #expect(abs(progress.remainingTimeS - 180) < 10)
        #expect(!progress.hasArrived)
    }

    @Test func progressHalfwayIsHalfDistance() {
        let route = straightRoute
        let location = CLLocation(latitude: 47.370899, longitude: 8.5400)

        let progress = RouteService.progress(of: route, at: location)

        #expect(abs(progress.remainingDistanceM - 100) < 5)
        #expect(abs(progress.remainingTimeS - 90) < 10)
        #expect(!progress.hasArrived)
    }

    @Test func progressNearDestinationDetectsArrival() {
        let route = straightRoute
        let location = CLLocation(latitude: 47.371790, longitude: 8.5400)

        let progress = RouteService.progress(of: route, at: location)

        #expect(progress.remainingDistanceM < 10)
        #expect(progress.hasArrived)
    }

    /// Abseits des Pfads: Restweg wird ab dem nächstgelegenen Punkt auf der
    /// Route gemessen, nicht ab der Luftlinie zum Ziel.
    @Test func progressOffPathSnapsToNearestSegment() {
        let route = straightRoute
        // ~20 m östlich des Streckenmittelpunkts.
        let location = CLLocation(latitude: 47.370899, longitude: 8.540265)

        let progress = RouteService.progress(of: route, at: location)

        #expect(abs(progress.remainingDistanceM - 100) < 5)
    }

    /// Korridor-Distanz: Punkte auf bzw. neben der Route liefern die
    /// senkrechte Distanz zum nächstgelegenen Segment.
    @Test func distanceToRouteMeasuresPerpendicularOffset() {
        let route = straightRoute

        let onPath = CLLocationCoordinate2D(latitude: 47.370899, longitude: 8.5400)
        #expect(RouteService.distance(from: onPath, to: route) < 2)

        // ~20 m östlich des Streckenmittelpunkts.
        let offPath = CLLocationCoordinate2D(latitude: 47.370899, longitude: 8.540265)
        let offDistance = RouteService.distance(from: offPath, to: route)
        #expect(abs(offDistance - 20) < 3)

        // ~100 m südlich des Starts: Distanz zum Startpunkt, nicht zur
        // Verlängerung des Segments.
        let behindStart = CLLocationCoordinate2D(latitude: 47.369101, longitude: 8.5400)
        let behindDistance = RouteService.distance(from: behindStart, to: route)
        #expect(abs(behindDistance - 100) < 5)
    }

    /// Route mit Knick: Restweg folgt beiden Segmenten.
    @Test func progressFollowsMultiSegmentRoute() {
        let corner = CLLocationCoordinate2D(latitude: 47.370899, longitude: 8.5400)
        let end = CLLocationCoordinate2D(latitude: 47.370899, longitude: 8.541327) // ~100 m östlich vom Knick
        let route = ActiveRoute(
            destinationName: "Test-WC",
            destinationCoordinate: end,
            coordinates: [
                CLLocationCoordinate2D(latitude: 47.3700, longitude: 8.5400),
                corner,
                end,
            ],
            totalDistanceM: 200,
            expectedTravelTimeS: 180
        )
        let start = CLLocation(latitude: 47.3700, longitude: 8.5400)

        let progress = RouteService.progress(of: route, at: start)

        #expect(abs(progress.remainingDistanceM - 200) < 8)
    }

    // MARK: - Nächstes Manöver (Richtungspfeile)

    /// Route mit 90°-Knick nach Osten: vom Start aus ist das nächste
    /// Manöver "rechts abbiegen" in ~100 m.
    @Test func maneuverDetectsRightTurnAhead() {
        let route = cornerRoute
        let start = CLLocation(latitude: 47.3700, longitude: 8.5400)

        let maneuver = RouteService.nextManeuver(of: route, at: start)

        #expect(maneuver?.direction == .right)
        if let maneuver {
            #expect(abs(maneuver.distanceM - 100) < 8)
        }
    }

    /// Nach dem Knick (auf dem Ost-Segment) gibt es keinen weiteren Knick:
    /// geradeaus bis zum Ziel.
    @Test func maneuverAfterTurnIsStraight() {
        let route = cornerRoute
        // ~30 m östlich des Knicks, auf dem letzten Segment.
        let afterCorner = CLLocation(latitude: 47.370899, longitude: 8.540398)

        let maneuver = RouteService.nextManeuver(of: route, at: afterCorner)

        #expect(maneuver?.direction == .straight)
    }

    /// Gerade Route ohne Knick: durchgehend geradeaus, Distanz = Restweg.
    @Test func maneuverOnStraightRouteIsStraight() {
        let route = straightRoute
        let start = CLLocation(latitude: 47.3700, longitude: 8.5400)

        let maneuver = RouteService.nextManeuver(of: route, at: start)

        #expect(maneuver?.direction == .straight)
        if let maneuver {
            #expect(abs(maneuver.distanceM - 200) < 8)
        }
    }

    /// Spiegelbild des Ost-Knicks: Abbiegen nach Westen ist links.
    @Test func maneuverDetectsLeftTurnAhead() {
        let corner = CLLocationCoordinate2D(latitude: 47.370899, longitude: 8.5400)
        let end = CLLocationCoordinate2D(latitude: 47.370899, longitude: 8.538673) // ~130 m westlich
        let route = ActiveRoute(
            destinationName: "Test-Apotheke",
            destinationCoordinate: end,
            coordinates: [
                CLLocationCoordinate2D(latitude: 47.3700, longitude: 8.5400),
                corner,
                end,
            ],
            totalDistanceM: 230,
            expectedTravelTimeS: 200
        )
        let start = CLLocation(latitude: 47.3700, longitude: 8.5400)

        let maneuver = RouteService.nextManeuver(of: route, at: start)

        #expect(maneuver?.direction == .left)
    }

    // MARK: - Egozentrische Ausrichtung (Blickrichtung)

    /// Route ~120 m nach Osten.
    private var eastRoute: ActiveRoute {
        let start = CLLocationCoordinate2D(latitude: 47.3700, longitude: 8.5400)
        let end = CLLocationCoordinate2D(latitude: 47.3700, longitude: 8.541593) // ~120 m östlich
        return ActiveRoute(
            destinationName: "Test-Ost",
            destinationCoordinate: end,
            coordinates: [start, end],
            totalDistanceM: 120,
            expectedTravelTimeS: 110
        )
    }

    /// Szenario aus dem Feldtest: Route führt nach Osten, man schaut aber nach
    /// Süden – aus Sicht des Users muss man nach LINKS. Die Route knickt nur ab,
    /// also eine sanfte "leicht links halten"-Ansage (kein "abbiegen"), "jetzt".
    @Test func maneuverReorientsSlightLeftWhenFacingSouthOnEastRoute() {
        let route = eastRoute
        let start = CLLocation(latitude: 47.3700, longitude: 8.5400)

        let maneuver = RouteService.nextManeuver(of: route, at: start, heading: 180)

        #expect(maneuver?.direction == .slightLeft)
        #expect(maneuver?.distanceM == 0)
        #expect(maneuver?.instruction == "Jetzt leicht links halten")
    }

    /// Spiegelbild: Route nach Norden, Blick nach Osten ⇒ leicht links halten.
    @Test func maneuverReorientsSlightLeftWhenFacingEastOnNorthRoute() {
        let route = straightRoute
        let start = CLLocation(latitude: 47.3700, longitude: 8.5400)

        let maneuver = RouteService.nextManeuver(of: route, at: start, heading: 90)

        #expect(maneuver?.direction == .slightLeft)
    }

    /// Route nach Norden, Blick nach Westen ⇒ leicht rechts halten.
    @Test func maneuverReorientsSlightRightWhenFacingWestOnNorthRoute() {
        let route = straightRoute
        let start = CLLocation(latitude: 47.3700, longitude: 8.5400)

        let maneuver = RouteService.nextManeuver(of: route, at: start, heading: 270)

        #expect(maneuver?.direction == .slightRight)
    }

    /// Deutliche, aber noch nicht entgegengesetzte Fehlausrichtung (hier ~130°
    /// neben der Route) wird als volles seitliches Abbiegen angesagt.
    @Test func maneuverReorientsFullTurnWhenStronglyMisaligned() {
        let route = straightRoute // nach Norden
        let start = CLLocation(latitude: 47.3700, longitude: 8.5400)

        let maneuver = RouteService.nextManeuver(of: route, at: start, heading: 130)

        #expect(maneuver?.direction == .left)
    }

    /// Blickt man (annähernd) entgegengesetzt zur Route – hier ~170° daneben –,
    /// wird ein "Umdrehen" angesagt (die Seite links/rechts ist dann uneindeutig).
    @Test func maneuverReorientsTurnAroundWhenFacingBackwards() {
        let route = straightRoute // nach Norden
        let start = CLLocation(latitude: 47.3700, longitude: 8.5400)

        let maneuver = RouteService.nextManeuver(of: route, at: start, heading: 170)

        #expect(maneuver?.direction == .turnAround)
        #expect(maneuver?.distanceM == 0)
        #expect(maneuver?.instruction == "Bitte umdrehen")
    }

    /// Genau entgegengesetzte Blickrichtung (180° neben der Route) ⇒ umdrehen.
    @Test func maneuverReorientsTurnAroundWhenFacingExactlyBackwards() {
        let route = straightRoute // nach Norden
        let start = CLLocation(latitude: 47.3700, longitude: 8.5400)

        let maneuver = RouteService.nextManeuver(of: route, at: start, heading: 180)

        #expect(maneuver?.direction == .turnAround)
    }

    /// Grob zur Route ausgerichtet: die egozentrische Korrektur greift nicht,
    /// die Anweisung folgt wieder der Routengeometrie (Knick nach rechts).
    @Test func maneuverKeepsGeometryTurnWhenAligned() {
        let route = cornerRoute
        let start = CLLocation(latitude: 47.3700, longitude: 8.5400)

        // Blickrichtung ~Nord = Richtung des ersten Segments → keine Korrektur.
        let maneuver = RouteService.nextManeuver(of: route, at: start, heading: 0)

        #expect(maneuver?.direction == .right)
    }

    /// Ausgerichtet auf gerader Route: geradeaus (keine Fehlausrichtung).
    @Test func maneuverStraightWhenAlignedOnStraightRoute() {
        let route = straightRoute
        let start = CLLocation(latitude: 47.3700, longitude: 8.5400)

        let maneuver = RouteService.nextManeuver(of: route, at: start, heading: 0)

        #expect(maneuver?.direction == .straight)
    }

    // MARK: - Distanz entlang der Route (Barrieren-Liste)

    /// Punkt auf halber Strecke: ~100 m ab Start entlang der Route.
    @Test func distanceAlongRouteAtMidpoint() {
        let route = straightRoute
        let midpoint = CLLocationCoordinate2D(latitude: 47.370899, longitude: 8.5400)

        let along = RouteService.distanceAlongRoute(to: midpoint, on: route)

        #expect(abs(along - 100) < 5)
    }

    /// Punkt neben der Route: zählt die Weglänge bis zur Projektion auf
    /// das nächstgelegene Segment, nicht die Luftlinie.
    @Test func distanceAlongRouteSnapsOffPathPoint() {
        let route = straightRoute
        // ~20 m östlich des Streckenmittelpunkts.
        let offPath = CLLocationCoordinate2D(latitude: 47.370899, longitude: 8.540265)

        let along = RouteService.distanceAlongRoute(to: offPath, on: route)

        #expect(abs(along - 100) < 5)
    }

    /// Knick-Route: Punkt auf dem zweiten Segment liegt hinter dem ganzen
    /// ersten Segment (~100 m) plus Anteil des zweiten (~50 m).
    @Test func distanceAlongRouteFollowsMultiSegmentRoute() {
        let route = cornerRoute
        // ~50 m östlich des Knicks, auf dem zweiten Segment.
        let onSecondSegment = CLLocationCoordinate2D(latitude: 47.370899, longitude: 8.540663)

        let along = RouteService.distanceAlongRoute(to: onSecondSegment, on: route)

        #expect(abs(along - 150) < 8)
    }

    /// Start- und Zielpunkt liefern 0 bzw. die volle Routenlänge.
    @Test func distanceAlongRouteAtEndpoints() {
        let route = straightRoute

        let atStart = RouteService.distanceAlongRoute(
            to: CLLocationCoordinate2D(latitude: 47.3700, longitude: 8.5400),
            on: route
        )
        let atEnd = RouteService.distanceAlongRoute(to: route.destinationCoordinate, on: route)

        #expect(atStart < 2)
        #expect(abs(atEnd - 200) < 5)
    }

    // MARK: - Karten-Ausrichtung (Anfangs-Fahrtrichtung)

    /// Kompasskurs für die vier Haupthimmelsrichtungen ab einem Startpunkt.
    @Test func bearingPointsInCardinalDirections() {
        let start = CLLocationCoordinate2D(latitude: 47.3700, longitude: 8.5400)
        let north = CLLocationCoordinate2D(latitude: 47.3710, longitude: 8.5400)
        let east = CLLocationCoordinate2D(latitude: 47.3700, longitude: 8.5420)
        let south = CLLocationCoordinate2D(latitude: 47.3690, longitude: 8.5400)
        let west = CLLocationCoordinate2D(latitude: 47.3700, longitude: 8.5380)

        #expect(abs(RouteService.bearingDegrees(from: start, to: north)) < 2)
        #expect(abs(RouteService.bearingDegrees(from: start, to: east) - 90) < 2)
        #expect(abs(RouteService.bearingDegrees(from: start, to: south) - 180) < 2)
        #expect(abs(RouteService.bearingDegrees(from: start, to: west) - 270) < 2)
    }

    /// Gerade Route Richtung Norden: Anfangsrichtung ~0° (Nord).
    @Test func initialBearingOnStraightRouteIsNorth() {
        let bearing = RouteService.initialBearingDegrees(of: straightRoute)
        #expect(bearing < 2 || bearing > 358)
    }

    /// Knick-Route (erst Norden, dann Osten): die Anfangsrichtung folgt dem
    /// ersten Segment nach Norden, nicht dem Ziel im Nordosten.
    @Test func initialBearingFollowsFirstSegment() {
        let bearing = RouteService.initialBearingDegrees(of: cornerRoute)
        #expect(bearing < 5 || bearing > 355)
    }

    /// Kurze Rausch-Segmente am Start verfälschen die Anfangsrichtung nicht:
    /// ein winziger Schlenker nach Westen, dann klar nach Osten → ~90°.
    @Test func initialBearingIgnoresShortNoiseAtStart() {
        let start = CLLocationCoordinate2D(latitude: 47.3700, longitude: 8.5400)
        // ~2 m westlich (Rauschen), danach ~120 m klar nach Osten.
        let noise = CLLocationCoordinate2D(latitude: 47.3700, longitude: 8.539973)
        let east = CLLocationCoordinate2D(latitude: 47.3700, longitude: 8.541593)
        let route = ActiveRoute(
            destinationName: "Test-Ost",
            destinationCoordinate: east,
            coordinates: [start, noise, east],
            totalDistanceM: 125,
            expectedTravelTimeS: 110
        )

        let bearing = RouteService.initialBearingDegrees(of: route)
        #expect(abs(bearing - 90) < 5)
    }

    /// Auf dem ersten Segment (Norden) zeigt die Fahrtrichtung nach Norden.
    @Test func travelBearingOnFirstSegmentIsNorth() {
        let route = cornerRoute
        let start = CLLocation(latitude: 47.3700, longitude: 8.5400)

        let bearing = RouteService.travelBearingDegrees(of: route, at: start)

        #expect(bearing != nil)
        if let bearing {
            #expect(bearing < 5 || bearing > 355)
        }
    }

    /// Nach dem Knick (auf dem Ost-Segment) zeigt die Fahrtrichtung nach
    /// Osten – die Karte dreht sich also mit dem Rechtsknick mit.
    @Test func travelBearingAfterTurnIsEast() {
        let route = cornerRoute
        // ~30 m östlich des Knicks, klar auf dem zweiten Segment.
        let afterCorner = CLLocation(latitude: 47.370899, longitude: 8.540398)

        let bearing = RouteService.travelBearingDegrees(of: route, at: afterCorner)

        #expect(bearing != nil)
        if let bearing {
            #expect(abs(bearing - 90) < 8)
        }
    }

    /// Spiegelbild: nach einem Linksknick zeigt die Fahrtrichtung nach Westen.
    @Test func travelBearingAfterLeftTurnIsWest() {
        let corner = CLLocationCoordinate2D(latitude: 47.370899, longitude: 8.5400)
        let end = CLLocationCoordinate2D(latitude: 47.370899, longitude: 8.538673) // ~130 m westlich
        let route = ActiveRoute(
            destinationName: "Test-Apotheke",
            destinationCoordinate: end,
            coordinates: [
                CLLocationCoordinate2D(latitude: 47.3700, longitude: 8.5400),
                corner,
                end,
            ],
            totalDistanceM: 230,
            expectedTravelTimeS: 200
        )
        // ~30 m westlich des Knicks, auf dem zweiten Segment.
        let afterCorner = CLLocation(latitude: 47.370899, longitude: 8.539602)

        let bearing = RouteService.travelBearingDegrees(of: route, at: afterCorner)

        #expect(bearing != nil)
        if let bearing {
            #expect(abs(bearing - 270) < 8)
        }
    }

    // MARK: - Einrasten auf die Route (Standortpunkt)

    /// Punkt neben der Route rastet seitlich auf die Linie ein: der Fusspunkt
    /// liegt auf der Route, der Abstand entspricht dem seitlichen Versatz.
    @Test func snappedLocationProjectsOntoRoute() {
        let route = straightRoute
        // ~20 m östlich des Streckenmittelpunkts.
        let location = CLLocation(latitude: 47.370899, longitude: 8.540265)

        let snap = RouteService.snappedLocation(on: route, at: location)

        #expect(abs(snap.offsetM - 20) < 3)
        // Eingerastet: Länge zurück auf die Linie (8.5400), Breite ~unverändert.
        #expect(abs(snap.coordinate.longitude - 8.5400) < 0.00005)
        #expect(abs(snap.coordinate.latitude - 47.370899) < 0.0002)
    }

    /// Punkt direkt auf der Route: Versatz ~0, Fusspunkt ~identisch.
    @Test func snappedLocationOnRouteKeepsPosition() {
        let route = straightRoute
        let location = CLLocation(latitude: 47.370899, longitude: 8.5400)

        let snap = RouteService.snappedLocation(on: route, at: location)

        #expect(snap.offsetM < 2)
        #expect(abs(snap.coordinate.latitude - 47.370899) < 0.0002)
        #expect(abs(snap.coordinate.longitude - 8.5400) < 0.00005)
    }

    // MARK: - Wegpunkt-Verdichtung (AR-Bodenpfad)

    /// Gerade 200-m-Route auf 2-m-Raster verdichtet: Start und Ziel bleiben,
    /// kein Teilstück ist mehr als ~2 m lang.
    @Test func densifyInsertsPointsWithinSpacing() {
        let coordinates = straightRoute.coordinates
        let dense = RouteService.densify(coordinates, maxSpacingM: 2)

        #expect(dense.count > 90)
        #expect(abs(dense.first!.latitude - coordinates.first!.latitude) < 1e-9)
        #expect(abs(dense.last!.latitude - coordinates.last!.latitude) < 1e-9)

        var maxGap = 0.0
        for i in 1..<dense.count {
            let gap = CLLocation(latitude: dense[i - 1].latitude, longitude: dense[i - 1].longitude)
                .distance(from: CLLocation(latitude: dense[i].latitude, longitude: dense[i].longitude))
            maxGap = max(maxGap, gap)
        }
        #expect(maxGap < 2.5)
    }

    /// Bereits kurze Segmente (unter dem Raster) bleiben unverändert.
    @Test func densifyKeepsShortSegments() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 47.3700, longitude: 8.5400),
            CLLocationCoordinate2D(latitude: 47.370009, longitude: 8.5400), // ~1 m
        ]
        let dense = RouteService.densify(coordinates, maxSpacingM: 2)
        #expect(dense.count == 2)
    }

    /// Knick-Route: die originalen Stützpunkte (Start, Knick, Ziel) bleiben
    /// erhalten, dazwischen wird verdichtet.
    @Test func densifyPreservesOriginalVertices() {
        let dense = RouteService.densify(cornerRoute.coordinates, maxSpacingM: 5)
        let corner = CLLocationCoordinate2D(latitude: 47.370899, longitude: 8.5400)
        let containsCorner = dense.contains {
            abs($0.latitude - corner.latitude) < 1e-9 && abs($0.longitude - corner.longitude) < 1e-9
        }
        #expect(containsCorner)
        #expect(dense.count > cornerRoute.coordinates.count)
    }

    /// Route ~100 m Norden, dann 90° nach Osten (~100 m).
    private var cornerRoute: ActiveRoute {
        let corner = CLLocationCoordinate2D(latitude: 47.370899, longitude: 8.5400)
        let end = CLLocationCoordinate2D(latitude: 47.370899, longitude: 8.541327)
        return ActiveRoute(
            destinationName: "Test-WC",
            destinationCoordinate: end,
            coordinates: [
                CLLocationCoordinate2D(latitude: 47.3700, longitude: 8.5400),
                corner,
                end,
            ],
            totalDistanceM: 200,
            expectedTravelTimeS: 180
        )
    }

    // MARK: - Turn-by-turn-Schritte (StepManeuver / RouteStep)

    /// Die ORS-Instruktionstypen werden korrekt auf Manöver abgebildet.
    @Test func stepManeuverMapsORSTypes() {
        #expect(StepManeuver.fromORSType(0) == .left)
        #expect(StepManeuver.fromORSType(1) == .right)
        #expect(StepManeuver.fromORSType(4) == .slightLeft)
        #expect(StepManeuver.fromORSType(5) == .slightRight)
        #expect(StepManeuver.fromORSType(6) == .straight)
        #expect(StepManeuver.fromORSType(10) == .arrive)
        #expect(StepManeuver.fromORSType(11) == .depart)
        // Unbekannter Typ fällt auf "geradeaus" zurück.
        #expect(StepManeuver.fromORSType(99) == .straight)
    }

    /// Ein Abbiege-Schritt mit Strasse zeigt "auf <Strasse>" als Wegangabe.
    @Test func routeStepBuildsInstructionFromManeuver() {
        let step = RouteStep(
            id: 0,
            maneuver: .left,
            streetName: "Marktgasse",
            distanceM: 40,
            coordinate: CLLocationCoordinate2D(latitude: 47.37, longitude: 8.54)
        )
        #expect(step.instruction == "Links abbiegen")
        #expect(step.wayText == "auf Marktgasse")
    }

    /// Ein Fallback-Schritt (nur Text) zeigt den Text und keine separate
    /// Wegangabe (die Strasse steckt bereits im Text).
    @Test func routeStepUsesProvidedTextForFallback() {
        let step = RouteStep(
            id: 1,
            maneuver: .right,
            providedText: "Nach rechts auf die Limmatgasse",
            distanceM: 25,
            coordinate: CLLocationCoordinate2D(latitude: 47.37, longitude: 8.54)
        )
        #expect(step.instruction == "Nach rechts auf die Limmatgasse")
        #expect(step.wayText == nil)
    }

    /// Ohne Strassenname bleibt die Wegangabe leer.
    @Test func routeStepWithoutStreetHasNoWayText() {
        let step = RouteStep(
            id: 2,
            maneuver: .straight,
            distanceM: 60,
            coordinate: CLLocationCoordinate2D(latitude: 47.37, longitude: 8.54)
        )
        #expect(step.instruction == "Geradeaus weiter")
        #expect(step.wayText == nil)
    }

    /// Best-effort-Ableitung des Manövers aus dem MapKit-Anweisungstext.
    @Test func stepManeuverFromTextDetectsDirection() {
        #expect(StepManeuver.fromText("Nach links abbiegen", isFirst: false) == .left)
        #expect(StepManeuver.fromText("Leicht rechts halten", isFirst: false) == .slightRight)
        #expect(StepManeuver.fromText("", isFirst: true) == .depart)
        #expect(StepManeuver.fromText("Sie haben Ihr Ziel erreicht", isFirst: false) == .arrive)
    }

    // MARK: - Route, die dicht an sich selbst vorbeiführt

    /// Feldtest-Fall: Die Route führt 300 m nach Norden, 20 m nach Osten und
    /// dieselbe Strecke wieder nach Süden zurück (Umweg über die nächste
    /// Brücke). Hin- und Rückweg liegen nur 20 m auseinander – ohne
    /// Fortschritts-Anker rastet die Verortung auf dem Rückweg ein.
    private var doublingBackRoute: ActiveRoute {
        let start = CLLocationCoordinate2D(latitude: 47.3700, longitude: 8.5400)
        let north = CLLocationCoordinate2D(latitude: 47.372695, longitude: 8.5400)
        let across = CLLocationCoordinate2D(latitude: 47.372695, longitude: 8.540265)
        let end = CLLocationCoordinate2D(latitude: 47.3700, longitude: 8.540265)
        return ActiveRoute(
            destinationName: "Test-WC gegenüber",
            destinationCoordinate: end,
            coordinates: [start, north, across, end],
            totalDistanceM: 620,
            expectedTravelTimeS: 560
        )
    }

    /// 100 m auf dem Hinweg, 12 m seitlich daneben: Der Rückweg liegt mit ~8 m
    /// näher. Mit dem Anker (bisher 100 m zurückgelegt) bleibt die Verortung
    /// auf dem Hinweg – der Restweg ist ~520 m, nicht ~100 m.
    @Test func progressStaysOnOutboundLegWithAnchor() {
        let route = doublingBackRoute
        let location = CLLocation(latitude: 47.370898, longitude: 8.540159)

        let progress = RouteService.progress(of: route, at: location, alongAnchorM: 100)

        #expect(abs(progress.remainingDistanceM - 520) < 15)
        #expect(!progress.hasArrived)
    }

    /// Dieselbe Stelle, Blick in Fahrtrichtung (Norden): Mit dem Anker kommt
    /// die korrekte Ansage "rechts abbiegen" in ~200 m – ohne ihn läge die
    /// Fahrtrichtung des Rückwegs (Süden) an und die App sagte "Bitte umdrehen".
    @Test func maneuverStaysOnOutboundLegWithAnchor() {
        let route = doublingBackRoute
        let location = CLLocation(latitude: 47.370898, longitude: 8.540159)

        let maneuver = RouteService.nextManeuver(
            of: route,
            at: location,
            heading: 0,
            alongAnchorM: 100
        )

        #expect(maneuver?.direction == .right)
        if let maneuver {
            #expect(abs(maneuver.distanceM - 200) < 15)
        }
    }

    /// Auch die Fahrtrichtung (Kartendrehung) folgt dem Hinweg nach Norden.
    @Test func travelBearingStaysOnOutboundLegWithAnchor() {
        let route = doublingBackRoute
        let location = CLLocation(latitude: 47.370898, longitude: 8.540159)

        let bearing = RouteService.travelBearingDegrees(of: route, at: location, alongAnchorM: 100)

        #expect(bearing != nil)
        if let bearing {
            #expect(abs(bearing) < 10 || abs(bearing - 360) < 10)
        }
    }

    /// Der Anker lenkt nur, er verfälscht nichts: Auf einer normalen Route
    /// liefert die Verortung mit passendem Anker dasselbe Ergebnis wie ohne.
    @Test func anchorDoesNotChangeStraightRouteProgress() {
        let route = straightRoute
        let location = CLLocation(latitude: 47.370899, longitude: 8.5400)

        let anchored = RouteService.progress(of: route, at: location, alongAnchorM: 100)
        let free = RouteService.progress(of: route, at: location)

        #expect(abs(anchored.remainingDistanceM - free.remainingDistanceM) < 1)
    }

    /// Verortung liefert Segment, Restweg und zurückgelegten Weg konsistent.
    @Test func locateReportsAlongAndRemaining() {
        let route = straightRoute
        let location = CLLocation(latitude: 47.370899, longitude: 8.540265)

        let fix = RouteService.locate(on: route, at: location)

        #expect(fix != nil)
        if let fix {
            #expect(fix.segmentIndex == 0)
            #expect(abs(fix.offsetM - 20) < 3)
            #expect(abs(fix.alongM - 100) < 5)
            #expect(abs(fix.remainingM - 100) < 5)
        }
    }

    // MARK: - Plausibilität der berechneten Route

    /// Ziel 40 m entfernt, Route 1,9 km: unplausibel (Feldtest-Screenshot).
    @Test func implausibleDetourDetectsAbsurdRouteForNearbyDestination() {
        #expect(RouteService.isImplausibleDetour(routeDistanceM: 1900, beelineM: 40))
    }

    /// Normale Umwege auf kurzen Strecken bleiben plausibel.
    @Test func implausibleDetourAcceptsOrdinaryShortDetours() {
        #expect(!RouteService.isImplausibleDetour(routeDistanceM: 200, beelineM: 40))
        #expect(!RouteService.isImplausibleDetour(routeDistanceM: 700, beelineM: 120))
    }

    /// Auf längeren Strecken wird gar nicht geprüft – dort sind grosse Umwege
    /// (Fluss, Bahngleise) normal und die Rollstuhl-Route bleibt gesetzt.
    @Test func implausibleDetourIgnoresLongTrips() {
        #expect(!RouteService.isImplausibleDetour(routeDistanceM: 3000, beelineM: 1200))
    }
}