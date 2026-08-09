// Barrier.swift
// Omina
//
// Eine Barriere aus der Datenbank (OSM-Import, siehe scripts/import_osm.py).
// Reines Datenmodell – ob eine Barriere für ein konkretes Profil kritisch ist,
// entscheidet `shouldWarn(barrier:profile:)` in Services/BarrierLogic.swift.

import Foundation
import CoreLocation

struct Barrier: Codable, Identifiable {
    let id: UUID
    let type: BarrierType
    let subtype: String?
    let value: Double?
    let unit: String?
    let latitude: Double
    let longitude: Double
    let valueSource: ValueSource
    let source: String
    let sourceId: String?
    let isActive: Bool
    let lastVerified: Date?

    enum CodingKeys: String, CodingKey {
        case id, type, subtype, value, unit, latitude, longitude, source
        case valueSource = "value_source"
        case sourceId = "source_id"
        case isActive = "is_active"
        case lastVerified = "last_verified"
    }
}

enum BarrierType: String, Codable, CaseIterable {
    case steps, curb, curbMissing = "curb_missing"
    case incline, surface, narrow, temporary

    /// Grobe Schwere-Rangfolge (höher = schwerwiegender). Dient dazu, bei
    /// mehreren Barrieren am exakt selben Punkt die repräsentative für
    /// Karten-Marker und Listenzeile zu wählen.
    var severityRank: Int {
        switch self {
        case .steps:       return 6
        case .narrow:      return 5
        case .curb:        return 4
        case .curbMissing: return 3
        case .incline:     return 2
        case .surface:     return 1
        case .temporary:   return 0
        }
    }
}

/// Woher der Zahlenwert einer Barriere stammt.
enum ValueSource: String, Codable {
    /// Wert direkt aus einem OSM-Tag gelesen.
    case measured
    /// Wert aus dem Default-Mapping des Imports (NFA-15: im Zweifel warnen).
    case estimated
    /// Wert manuell gepflegt.
    case manual
}

extension Barrier {
    /// Position der Barriere – spart an den vielen Aufrufstellen das
    /// wiederholte Zusammensetzen aus `latitude`/`longitude`.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Vergleicht zwei am selben Ort liegende Barrieren: zuerst nach
    /// Typ-Schwere, dann nach Wert (grösser = schwerer), zuletzt stabiler
    /// Tie-Break über die ID – damit die Wahl der Stellvertreter-Barriere
    /// über Neuberechnungen hinweg gleich bleibt.
    func isMoreSevere(than other: Barrier) -> Bool {
        if type.severityRank != other.type.severityRank {
            return type.severityRank > other.type.severityRank
        }
        let mine = value ?? 0
        let theirs = other.value ?? 0
        if mine != theirs { return mine > theirs }
        return id.uuidString > other.id.uuidString
    }
}
