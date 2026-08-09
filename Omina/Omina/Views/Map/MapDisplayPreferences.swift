// MapDisplayPreferences.swift
// Omina
//
// View-Modifier, der die geteilten Karten-Präferenzen (Kartenstil und
// Hell-/Dunkel-Modus) auf eine Map anwendet. Getrennt vom Store gehalten:
// MapPreferences hält den Zustand, dieser Modifier bringt ihn auf die Karte.

import SwiftUI
import MapKit

/// Wendet die geteilten Karten-Präferenzen auf eine Map an. Direkt auf der
/// Map (vor Overlays/Sheets) anwenden, damit das erzwungene Farbschema nur
/// die Karte betrifft und nicht die restliche UI.
struct MapDisplayPreferencesModifier: ViewModifier {
    @ObservedObject var preferences: MapPreferences
    @Environment(\.colorScheme) private var systemColorScheme

    func body(content: Content) -> some View {
        content
            .mapStyle(preferences.style.mapKitStyle)
            .environment(\.colorScheme, preferences.appearance.colorScheme ?? systemColorScheme)
    }
}

extension View {
    /// Karten-Stil (Karte/Satellit) und Hell-/Dunkel-Modus aus den
    /// geteilten MapPreferences anwenden. Ohne Argument werden die
    /// geteilten `MapPreferences.shared` verwendet (Auflösung im
    /// MainActor-Kontext, nicht im Default-Argument).
    @MainActor
    func mapDisplayPreferences(_ preferences: MapPreferences? = nil) -> some View {
        modifier(MapDisplayPreferencesModifier(preferences: preferences ?? .shared))
    }
}
