// MapPreferences.swift
// Omina
//
// Nutzer-Präferenzen für die Kartendarstellung: Hell-/Dunkel-Modus und
// Karten- vs. Satellitenansicht. Wird von allen Map-Instanzen geteilt
// (Hauptkarte, AR-Mini-Karte, Routen-Panels) und in UserDefaults persistiert.
// Wählbar über das Ebenen-Menü auf der Karte und in den Einstellungen.

import SwiftUI
import MapKit
import Combine

/// Hell-/Dunkel-Darstellung der Karte.
enum MapAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Automatisch"
        case .light:  return "Hell"
        case .dark:   return "Dunkel"
        }
    }

    /// Erzwungenes Farbschema; nil folgt dem System.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Karten- vs. Satellitenansicht.
enum MapStyleChoice: String, CaseIterable, Identifiable {
    case standard, satellite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard:  return "Karte"
        case .satellite: return "Satellit"
        }
    }

    /// SF-Symbol für die Auswahl-Kacheln im Karteneinstellungs-Overlay.
    var symbol: String {
        switch self {
        case .standard:  return "map.fill"
        case .satellite: return "globe.europe.africa.fill"
        }
    }

    /// Hybrid statt reinem Satellit, damit Strassennamen und die
    /// Routen-Polyline lesbar bleiben.
    var mapKitStyle: MapStyle {
        switch self {
        case .standard:  return .standard
        case .satellite: return .hybrid
        }
    }
}

@MainActor
final class MapPreferences: ObservableObject {
    static let shared = MapPreferences()

    private static let appearanceKey = "omina.mapAppearance"
    private static let styleKey = "omina.mapStyle"

    @Published var appearance: MapAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    @Published var style: MapStyleChoice {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: Self.styleKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        appearance = MapAppearance(rawValue: defaults.string(forKey: Self.appearanceKey) ?? "") ?? .system
        style = MapStyleChoice(rawValue: defaults.string(forKey: Self.styleKey) ?? "") ?? .standard
    }
}

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