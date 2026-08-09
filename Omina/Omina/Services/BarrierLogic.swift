// BarrierLogic.swift
// Omina – v2.0 | shouldWarn() Kernlogik

import Foundation
import Combine

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

extension Barrier {
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

enum ValueSource: String, Codable {
    case measured, estimated, manual
}

struct BarrierWarning: Identifiable {
    let id = UUID()
    let barrier: Barrier
    let distance: Double
    let userLimit: String
    let barrierValue: String
    let alternative: Alternative?
}

struct Alternative {
    let description: String
    let direction: Double
    let distance: Double
}

// MARK: - shouldWarn (FA-23, FA-24)

func shouldWarn(barrier: Barrier, profile: UserProfile) -> Bool {
    switch barrier.type {
    case .curbMissing:
        return true // FA-26
        
    case .steps:
        return !profile.wheelchairType.canClimbStairs // FA-25, FA-47
        
    case .curb:
        guard let height = barrier.value else { return true } // NFA-15
        return height > profile.effectiveMaxCurb
        
    case .incline:
        guard let incline = barrier.value else { return true }
        if barrier.valueSource == .estimated {
            return incline >= profile.effectiveMaxIncline
        }
        return incline > profile.effectiveMaxIncline
        
    case .surface:
        // Material (surface), Ebenheit (smoothness) und Wegequalität
        // (tracktype) aus OSM – siehe OSMSurfaceRating.
        guard let subtype = barrier.subtype else { return false }
        return OSMSurfaceRating.isBlocking(
            subtype: subtype,
            tolerance: profile.effectiveSurfaceTolerance
        )

    case .narrow:
        guard let width = barrier.value else { return true }
        return width < Double(profile.effectiveWidthNeeded)
        
    case .temporary:
        return true
    }
}

// MARK: - Warnung generieren

func generateWarning(barrier: Barrier, profile: UserProfile, distance: Double, alternative: Alternative? = nil) -> BarrierWarning? {
    guard shouldWarn(barrier: barrier, profile: profile) else { return nil }
    
    let (barrierValue, userLimit): (String, String) = {
        switch barrier.type {
        case .steps:
            let count = barrier.value.map { "\(Int($0))" } ?? "?"
            return ("Stufen: \(count)", "Nicht passierbar")
        case .curb, .curbMissing:
            let h = barrier.value.map { "\(Int($0))cm" } ?? "unbekannt"
            return ("Bordstein: \(h)", "Dein Limit: \(Int(profile.effectiveMaxCurb))cm")
        case .incline:
            let v = barrier.value.map { "\(Int($0))%" } ?? "unbekannt"
            return ("Steigung: \(v)", "Dein Limit: \(Int(profile.effectiveMaxIncline))%")
        case .surface:
            let name = barrier.subtype.map(BarrierType.localizedSurface) ?? "unbekannt"
            return ("Oberfläche: \(name)", "Nicht in deiner Toleranz")
        case .narrow:
            let w = barrier.value.map { "\(Int($0))cm" } ?? "unbekannt"
            return ("Engstelle: \(w)", "Du brauchst: \(profile.effectiveWidthNeeded)cm")
        case .temporary:
            return ("Temporäres Hindernis", "Weg blockiert")
        }
    }()
    
    return BarrierWarning(barrier: barrier, distance: distance, userLimit: userLimit, barrierValue: barrierValue, alternative: alternative)
}