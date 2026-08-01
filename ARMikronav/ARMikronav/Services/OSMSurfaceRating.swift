// OSMSurfaceRating.swift
// ARMikronav
//
// Bewertet die Oberflächen-Tags aus OpenStreetMap gegen die persönliche
// Oberflächen-Toleranz. Die Werte und ihre Bedeutung stammen aus dem
// OSM-Wiki, Projekt Rollstuhl-Routing:
// https://wiki.openstreetmap.org/wiki/Wheelchair_routing
//
// Drei Tags beschreiben dort denselben Sachverhalt aus verschiedenen Winkeln:
//   surface=*     Material des Belags (Asphalt, Pflaster, Kies, Sand …)
//   smoothness=*  Ebenheit; laut Wiki ist "intermediate" das, was Citybike,
//                 Rollstuhl und Kinderwagen noch fahren, "bad" braucht
//                 robuste Bereifung.
//   tracktype=*   Wegequalität; grade1 = befestigt/stark verdichtet,
//                 grade2 = Kies oder dicht gepackter Sand.
//
// Der OSM-Import (scripts/import_osm.py) legt sie als Barrieren vom Typ
// `surface` ab: das Material als reiner Wert ("sett"), Ebenheit und
// Wegequalität mit Präfix ("smoothness_bad", "tracktype_grade3"). Die
// Schwellen hier entsprechen denen, die RouteService als Restriktionen an das
// OSM-Routing schickt – Karte und Route bewerten damit dasselbe gleich.

import Foundation

enum OSMSurfaceRating {
    /// Präfix der Ebenheits-Subtypen (OSM `smoothness`).
    static let smoothnessPrefix = "smoothness_"
    /// Präfix der Wegequalitäts-Subtypen (OSM `tracktype`).
    static let trackTypePrefix = "tracktype_"

    /// Ist der Oberflächen-Subtyp einer Barriere für diese Toleranz ein
    /// Hindernis? Deckt Material, Ebenheit und Wegequalität ab.
    static func isBlocking(subtype: String, tolerance: SurfaceTolerance) -> Bool {
        if subtype.hasPrefix(smoothnessPrefix) {
            let value = String(subtype.dropFirst(smoothnessPrefix.count))
            return isBlocking(smoothness: value, tolerance: tolerance)
        }
        if subtype.hasPrefix(trackTypePrefix) {
            let value = String(subtype.dropFirst(trackTypePrefix.count))
            return isBlocking(trackType: value, tolerance: tolerance)
        }
        return isBlocking(surface: subtype, tolerance: tolerance)
    }

    // MARK: - surface=*

    /// Rauheit eines Belags. Die Zuordnung folgt der Surface-Tabelle des Wikis.
    enum Roughness: Int, Comparable {
        /// Asphalt, Beton, befestigt.
        case smooth = 0
        /// Pflastersteine, Betonplatten, verdichteter Belag, Feinkies.
        case slightlyUneven = 1
        /// Behauenes Kopfsteinpflaster (sett), feines Kopfsteinpflaster,
        /// Rasengittersteine.
        case uneven = 2
        /// Grobes Naturstein-Kopfsteinpflaster.
        case rough = 3
        /// Loser Untergrund: Kies, Sand, Erde, Gras, Schlamm.
        case loose = 4

        static func < (lhs: Roughness, rhs: Roughness) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Rauheit eines OSM-`surface`-Werts; unbekannte Werte gelten als glatt
    /// (nicht warnen, wo nichts bekannt ist – gewarnt wird über die Tags, die
    /// tatsächlich erfasst sind).
    static func roughness(of surface: String) -> Roughness {
        switch surface {
        case "asphalt", "concrete", "paved", "chipseal", "metal":
            return .smooth
        case "paving_stones", "concrete_plates", "concrete:plates",
             "compacted", "fine_gravel", "cobblestone:flattened",
             "sett:flattened", "wood":
            return .slightlyUneven
        case "sett", "cobblestone_fine", "grass_paver", "unhewn_cobblestone:flattened":
            return .uneven
        case "cobblestone", "cobblestone_coarse", "unhewn_cobblestone", "rock", "stone":
            return .rough
        case "gravel", "sand", "ground", "dirt", "earth", "mud", "grass",
             "pebblestone", "woodchips", "unpaved":
            return .loose
        default:
            return .smooth
        }
    }

    /// Gröbster Belag, der für diese Toleranz noch in Ordnung ist.
    private static func acceptedRoughness(for tolerance: SurfaceTolerance) -> Roughness {
        switch tolerance {
        case .smoothOnly: return .slightlyUneven
        case .fineCobble: return .uneven
        case .almostAll:  return .rough
        }
    }

    static func isBlocking(surface: String, tolerance: SurfaceTolerance) -> Bool {
        roughness(of: surface) > acceptedRoughness(for: tolerance)
    }

    // MARK: - smoothness=*

    /// Rangfolge der OSM-`smoothness`-Werte (0 = am besten).
    static func smoothnessRank(_ value: String) -> Int? {
        switch value {
        case "excellent":      return 0
        case "good":           return 1
        case "intermediate":   return 2
        case "bad":            return 3
        case "very_bad":       return 4
        case "horrible":       return 5
        case "very_horrible":  return 6
        case "impassable":     return 7
        default:               return nil
        }
    }

    /// Schlechteste Ebenheit, die für diese Toleranz noch in Ordnung ist –
    /// dieselben Stufen, die RouteService als `smoothness_type` ans Routing
    /// schickt.
    private static func acceptedSmoothnessRank(for tolerance: SurfaceTolerance) -> Int {
        switch tolerance {
        case .smoothOnly: return 1 // good
        case .fineCobble: return 2 // intermediate
        case .almostAll:  return 3 // bad
        }
    }

    static func isBlocking(smoothness: String, tolerance: SurfaceTolerance) -> Bool {
        guard let rank = smoothnessRank(smoothness) else { return false }
        return rank > acceptedSmoothnessRank(for: tolerance)
    }

    // MARK: - tracktype=*

    /// Rangfolge der OSM-`tracktype`-Werte (grade1 = am besten).
    static func trackTypeRank(_ value: String) -> Int? {
        switch value {
        case "grade1": return 1
        case "grade2": return 2
        case "grade3": return 3
        case "grade4": return 4
        case "grade5": return 5
        default:       return nil
        }
    }

    /// Schlechteste Wegequalität, die für diese Toleranz noch in Ordnung ist –
    /// dieselben Stufen, die RouteService als `track_type` ans Routing schickt.
    private static func acceptedTrackTypeRank(for tolerance: SurfaceTolerance) -> Int {
        switch tolerance {
        case .smoothOnly, .fineCobble: return 1 // grade1
        case .almostAll:               return 2 // grade2
        }
    }

    static func isBlocking(trackType: String, tolerance: SurfaceTolerance) -> Bool {
        guard let rank = trackTypeRank(trackType) else { return false }
        return rank > acceptedTrackTypeRank(for: tolerance)
    }
}