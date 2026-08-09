// BarrierWarning.swift
// Omina
//
// Eine für das eigene Profil kritische Barriere in Warn-Aufbereitung: der
// Vergleich "Wert der Barriere" gegen "eigenes Limit" in fertigen Textzeilen,
// wie ihn Annäherungs-Banner, System-Mitteilung und AR-Overlay anzeigen.
// Erzeugt wird sie ausschliesslich über `generateWarning(barrier:profile:…)`
// in Services/BarrierLogic.swift.

import Foundation

struct BarrierWarning: Identifiable {
    let id = UUID()
    let barrier: Barrier
    /// Distanz vom Standort zur Barriere (Meter).
    let distance: Double
    /// Eigenes Limit als Text, z. B. "Dein Limit: 3cm".
    let userLimit: String
    /// Wert der Barriere als Text, z. B. "Bordstein: 8cm".
    let barrierValue: String
    let alternative: Alternative?
}

/// Ausweichhinweis zu einer Barriere (Richtung und Distanz zur Alternative).
struct Alternative {
    let description: String
    /// Kompasskurs zur Alternative (Grad, 0 = Nord).
    let direction: Double
    /// Distanz zur Alternative (Meter).
    let distance: Double
}
