// Route.swift
// Omina
//
// Datenmodell der Navigation: die berechnete Route (`ActiveRoute`), ihr
// Fortschritt, die Verortung des Standorts darauf und die Manöver der
// Turn-by-turn-Liste.
//
// Bewusst frei von Berechnungslogik – wie eine Route entsteht und wie
// Fortschritt, Fusspunkt und Manöver daraus abgeleitet werden, steht in
// Services/RouteService.swift.

import Foundation
import CoreLocation

/// Wie die Route berechnet wurde.
enum RouteKind: Equatable {
    /// Fussgängerroute (MapKit) – der Standard. Die Geometrie kennt keine
    /// Barrieren; die Barrieren entlang der Strecke werden separat bewertet,
    /// angezeigt und angesagt.
    case walking
    /// Rollstuhlgerechte OSM-Route (OpenRouteService-Profil "wheelchair") mit
    /// den persönlichen Limits. Nur noch für die Alternativroute um eine
    /// konkrete Barriere herum.
    case wheelchair

    /// Beruht die Route auf dem OSM-Rollstuhl-Routing?
    var usesOSMWheelchairRouting: Bool { self == .wheelchair }

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
