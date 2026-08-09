// BarrierAnnotation.swift
// Omina
//
// SwiftUI-Annotation-Inhalt je Barrierentyp – wird von MapView in MapKit `Annotation`-Items
// platziert. SF Symbols + Systemfarben gemäß Konventionen.

import SwiftUI

extension BarrierType {
    var symbolName: String {
        switch self {
        case .steps:        return "stairs"
        case .curb:         return "arrow.up.to.line"                              // Kante hoch
        case .curbMissing:  return "nosign"                                        // kein Übergang möglich
        case .incline:      return "arrow.up.right"                                // Steigung
        case .surface:      return "circle.grid.3x3.fill"                          // Pflastersteine
        case .narrow:       return "arrow.right.and.line.vertical.and.arrow.left"  // Engstelle
        case .temporary:    return "cone.fill"                                     // Baustelle/Hindernis
        }
    }

    var tint: Color {
        switch self {
        case .steps, .curbMissing, .temporary: return .red
        case .curb, .incline:                   return .orange
        case .narrow, .surface:                 return .yellow
        }
    }

    var localizedLabel: String {
        switch self {
        case .steps:        return "Stufen"
        case .curb:         return "Bordstein"
        case .curbMissing:  return "Bordstein-Absenkung fehlt"
        case .incline:      return "Steigung"
        case .surface:      return "Oberfläche"
        case .narrow:       return "Engstelle"
        case .temporary:    return "Temporäres Hindernis"
        }
    }

    /// Deutsche Bezeichnung eines Oberflächen-Subtyps: OSM-`surface`-Werte wie
    /// "sett" oder "cobblestone", dazu die Ebenheit (`smoothness_*`) und die
    /// Wegequalität (`tracktype_*`) aus dem OSM-Import. Fällt bei unbekannten
    /// Werten auf eine bereinigte, gross geschriebene Form des Rohwerts zurück.
    nonisolated static func localizedSurface(_ subtype: String) -> String {
        if subtype.hasPrefix(OSMSurfaceRating.smoothnessPrefix) {
            return localizedSmoothness(
                String(subtype.dropFirst(OSMSurfaceRating.smoothnessPrefix.count))
            )
        }
        if subtype.hasPrefix(OSMSurfaceRating.trackTypePrefix) {
            let grade = String(subtype.dropFirst(OSMSurfaceRating.trackTypePrefix.count))
            return "Wegequalität \(grade.replacingOccurrences(of: "grade", with: "Stufe "))"
        }
        switch subtype {
        case "sett":
            return "Kopfsteinpflaster"
        case "cobblestone", "unhewn_cobblestone":
            return "Kopfsteinpflaster (grob)"
        case "cobblestone_coarse":
            return "grobes Kopfsteinpflaster"
        case "cobblestone_fine":
            return "feines Kopfsteinpflaster"
        case "paving_stones":
            return "Pflastersteine"
        case "gravel":
            return "Kies"
        case "fine_gravel":
            return "Feinkies"
        case "compacted":
            return "verdichteter Belag"
        case "sand":
            return "Sand"
        case "grass":
            return "Rasen"
        case "dirt", "ground", "earth", "mud":
            return "Naturboden"
        default:
            return subtype.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Deutsche Bezeichnung der OSM-`smoothness`-Stufen (Wiki-Tabelle:
    /// "intermediate" ist das, was Rollstuhl und Kinderwagen noch fahren).
    nonisolated static func localizedSmoothness(_ value: String) -> String {
        switch value {
        case "excellent":     return "sehr ebener Belag"
        case "good":          return "ebener Belag"
        case "intermediate":  return "leicht unebener Belag"
        case "bad":           return "unebener Belag"
        case "very_bad":      return "stark unebener Belag"
        case "horrible":      return "sehr grober Belag"
        case "very_horrible": return "extrem grober Belag"
        case "impassable":    return "nicht befahrbar"
        default:              return "unebener Belag"
        }
    }
}

struct BarrierAnnotation: View {
    let barrier: Barrier

    var body: some View {
        ZStack {
            Circle()
                .fill(barrier.type.tint)
                .frame(width: 32, height: 32)
                .shadow(radius: 2)
            Image(systemName: barrier.type.symbolName)
                .foregroundStyle(.white)
                .font(.system(size: 16, weight: .semibold))
        }
        .accessibilityLabel(barrier.type.localizedLabel)
    }
}