// AccessibilityStandard.swift
// ARMikronav
//
// Grenzwerte für rollstuhlgerechte Wege nach DIN 18024-1, wie sie das
// OpenStreetMap-Wiki im Abschnitt "Requirements for Wheelchair Accessible
// Routes" des Projekts Rollstuhl-Routing zusammenfasst:
// https://wiki.openstreetmap.org/wiki/Wheelchair_routing
//
// Wozu: Wo das eigene Profil keine Vorgabe macht oder OSM keinen Messwert
// liefert, sind das die Bezugswerte – für die gelockerte Routing-Stufe
// (RouteService), für die geschätzten Werte des OSM-Imports
// (scripts/import_osm.py) und als Vergleich in der Barrieren-Anzeige.
// Bewusst als eigene Konstanten, damit im Code nachvollziehbar bleibt,
// welche Zahl aus der Norm stammt und welche aus dem Nutzerprofil.

import Foundation

// `nonisolated` wie OSMSurfaceRating: reine Konstanten, die überall gelten –
// unabhängig davon, dass das Projekt sonst mit MainActor als Standard-
// Isolation baut.
nonisolated enum AccessibilityStandard {
    // MARK: - Längs- und Querneigung

    /// Längsneigung, die ohne Einschränkung als machbar gilt (%).
    static let maxInclinePercent: Double = 3
    /// Längsneigung, die mit Verweilplätzen alle `restIntervalM` noch
    /// zulässig ist (%) – im Handrollstuhl die praktische Obergrenze.
    static let maxInclineWithRestPercent: Double = 6
    /// Abstand der Verweilplätze bei 3–6 % Längsneigung (m).
    static let restIntervalM: Double = 10
    /// Zulässige Querneigung (%).
    static let maxCrossInclinePercent: Double = 2
    /// Maximale Rampenneigung (%).
    static let maxRampInclinePercent: Double = 6

    // MARK: - Breiten

    /// Mindestbreite eines Nebenwegs (cm).
    static let minSideWayWidthCm: Double = 90
    /// Empfohlene Breite eines Nebenwegs (cm).
    static let recommendedSideWayWidthCm: Double = 100
    /// Mindestbreite eines Hauptwegs (cm).
    static let minMainWayWidthCm: Double = 150
    /// Empfohlene Breite eines Hauptwegs (cm).
    static let recommendedMainWayWidthCm: Double = 200
    /// Mindestbreite einer Rampe zwischen den Radabweisern (cm).
    static let minRampWidthCm: Double = 120

    // MARK: - Kanten, Spalten, Oberfläche

    /// Maximale Schwellen- bzw. Bordsteinhöhe (cm).
    static let maxKerbHeightCm: Double = 3
    /// Maximale Spaltbreite quer zur Fahrtrichtung (cm).
    static let maxGapAcrossCm: Double = 3
    /// Maximale Spaltbreite parallel zur Fahrtrichtung, z. B. Roste (cm).
    static let maxGapAlongCm: Double = 0.5
    /// Maximale Unebenheit der Oberfläche (mm).
    static let maxSurfaceUnevennessMm: Double = 5

    // MARK: - Umrechnungen für das Routing

    /// Maximale Bordsteinhöhe in Metern (Einheit der ORS-Restriktionen).
    static var maxKerbHeightM: Double { maxKerbHeightCm / 100 }
    /// Mindestbreite eines Nebenwegs in Metern (Einheit der ORS-Restriktionen).
    static var minSideWayWidthM: Double { minSideWayWidthCm / 100 }
}