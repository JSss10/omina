// OpenRouteServiceDTO.swift
// Omina
//
// Request- und Response-Typen der OpenRouteService-Directions-API
// (Profil "wheelchair"). Getrennt vom RouteService gehalten, damit dort die
// Routing-Logik steht und hier ausschliesslich das Vertragsformat der API –
// inklusive der Stellen, an denen die persönlichen Limits aus dem UserProfile
// auf die von ORS erlaubten Stufen abgebildet werden.

import Foundation
import CoreLocation

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
struct ORSDirectionsResponse: Decodable {
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
