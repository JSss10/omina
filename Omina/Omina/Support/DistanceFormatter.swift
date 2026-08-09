// DistanceFormatter.swift
// Omina
//
// Einheitliche Distanzformatierung für die ganze App: Ab 1 km wird in
// Kilometern angezeigt (eine Nachkommastelle), darunter ausschliesslich in
// ganzen Metern. So bleibt die Angabe überall konsistent.

import Foundation

enum DistanceFormatter {
    /// Formatiert eine Distanz in Metern. Ab 1000 m → Kilometer (z. B.
    /// "1.4 km"), darunter ganze Meter (z. B. "780 m").
    static func string(fromMeters meters: Double) -> String {
        let safe = max(0, meters)
        if safe >= 1000 {
            return String(format: "%.1f km", safe / 1000)
        }
        return "\(Int(safe.rounded())) m"
    }

    /// Wie `string(fromMeters:)`, ergänzt um das Suffix „entfernt“.
    static func awayString(fromMeters meters: Double) -> String {
        string(fromMeters: meters) + " entfernt"
    }
}