// BarrierLogic.swift
// Omina
//
// Kernlogik der personalisierten Barrierenbewertung (FA-23, FA-24): Entscheidet
// für eine einzelne Barriere, ob sie für ein konkretes Nutzerprofil kritisch
// ist, und baut daraus die Warnung mit dem Vergleich "Wert der Barriere" gegen
// "eigenes Limit".
//
// Das Datenmodell dazu liegt in Models/Barrier.swift und
// Models/BarrierWarning.swift – hier steht ausschliesslich die Bewertung.

import Foundation

// MARK: - shouldWarn (FA-23, FA-24)

/// Ist die Barriere für dieses Profil kritisch? Grundsatz bei fehlenden Werten
/// ist NFA-15: im Zweifel warnen – lieber ein Hinweis zu viel als eine
/// Sackgasse vor Ort.
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
        // Geschätzte Werte (Default-Mapping des Imports) schon bei
        // Gleichstand melden – gemessene erst bei echter Überschreitung.
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

/// Baut die Warnung zu einer Barriere – oder `nil`, wenn sie für dieses Profil
/// gar nicht kritisch ist.
func generateWarning(
    barrier: Barrier,
    profile: UserProfile,
    distance: Double,
    alternative: Alternative? = nil
) -> BarrierWarning? {
    guard shouldWarn(barrier: barrier, profile: profile) else { return nil }

    let (barrierValue, userLimit) = warningTexts(for: barrier, profile: profile)

    return BarrierWarning(
        barrier: barrier,
        distance: distance,
        userLimit: userLimit,
        barrierValue: barrierValue,
        alternative: alternative
    )
}

/// Die beiden Textzeilen der Warnung: Wert der Barriere und eigenes Limit.
private func warningTexts(
    for barrier: Barrier,
    profile: UserProfile
) -> (barrierValue: String, userLimit: String) {
    switch barrier.type {
    case .steps:
        let count = barrier.value.map { "\(Int($0))" } ?? "?"
        return ("Stufen: \(count)", "Nicht passierbar")

    case .curb, .curbMissing:
        let height = barrier.value.map { "\(Int($0))cm" } ?? "unbekannt"
        return ("Bordstein: \(height)", "Dein Limit: \(Int(profile.effectiveMaxCurb))cm")

    case .incline:
        let incline = barrier.value.map { "\(Int($0))%" } ?? "unbekannt"
        return ("Steigung: \(incline)", "Dein Limit: \(Int(profile.effectiveMaxIncline))%")

    case .surface:
        let name = barrier.subtype.map(BarrierType.localizedSurface) ?? "unbekannt"
        return ("Oberfläche: \(name)", "Nicht in deiner Toleranz")

    case .narrow:
        let width = barrier.value.map { "\(Int($0))cm" } ?? "unbekannt"
        return ("Engstelle: \(width)", "Du brauchst: \(profile.effectiveWidthNeeded)cm")

    case .temporary:
        return ("Temporäres Hindernis", "Weg blockiert")
    }
}
