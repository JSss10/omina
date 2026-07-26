// POI.swift
// ARMikronav
//
// Point of Interest aus poi_accessibility (ginto + OSM Import).
// Geliefert von der RPC pois_within_radius mit explizitem lat/lng und Distanz.

import Foundation
import SwiftUI
import MapKit
import Supabase

// Codable (nicht nur Decodable): erlaubt das Zwischenspeichern der
// Altstadt-POIs im LocalDataStore für sofortige Anzeige beim nächsten Start.
struct POI: Codable, Identifiable {
    let id: UUID
    let name: String
    let category: String?
    let latitude: Double
    let longitude: Double
    let address: String?
    let wheelchairAccessible: String?
    let accessibilityDetails: [String: AnyJSON]?
    let source: String
    let distanceM: Double

    enum CodingKeys: String, CodingKey {
        case id, name, category, latitude, longitude, address, source
        case wheelchairAccessible = "wheelchair_accessible"
        case accessibilityDetails = "accessibility_details"
        case distanceM = "distance_m"
    }

    var accessStatus: POIAccessStatus {
        switch wheelchairAccessible?.lowercased() {
        case "yes":     return .accessible
        case "limited": return .limited
        case "no":      return .notAccessible
        default:        return .unknown
        }
    }

    // MARK: - ginto-Detailinformationen (accessibility_details JSONB)

    /// Bild-URLs des Ortes aus dem ginto-Import (accessibility_details.images,
    /// als Strings oder Objekte mit "url"). Leer, wenn keine Bilder vorliegen.
    var imageURLs: [URL] {
        guard case .array(let items)? = accessibilityDetails?["images"] else { return [] }
        return items.compactMap { item in
            switch item {
            case .string(let urlString):
                return URL(string: urlString)
            case .object(let dict):
                guard case .string(let urlString)? = dict["url"] else { return nil }
                return URL(string: urlString)
            default:
                return nil
            }
        }
    }

    /// Link auf die ginto-Detailseite des Eintrags (accessibility_details.ginto_url).
    var gintoURL: URL? {
        guard case .string(let urlString)? = accessibilityDetails?["ginto_url"] else { return nil }
        return URL(string: urlString)
    }

    /// Webseite des Ortes für die Detailansicht. Nimmt das erste vorhandene
    /// URL-Feld aus den Detaildaten (ohne Bezug auf die Datenquelle in der UI).
    var websiteURL: URL? {
        let candidateKeys = ["website", "homepage", "url", "ginto_url"]
        for key in candidateKeys {
            if case .string(let urlString)? = accessibilityDetails?[key],
               let url = normalizedURL(urlString) {
                return url
            }
        }
        return nil
    }

    /// Ergänzt fehlende Schemata (z. B. «www.beispiel.ch») zu einer gültigen URL.
    private func normalizedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://\(trimmed)")
    }

    /// Deutscher Kategorie-Name aus ginto (accessibility_details.categories[0].name),
    /// z.B. "Café" statt des DB-Keys "coffee".
    var categoryDisplayName: String? {
        guard case .array(let categories)? = accessibilityDetails?["categories"],
              case .object(let first)? = categories.first,
              case .string(let name)? = first["name"]
        else { return nil }
        return name
    }

    /// ginto-Bewertungen je Rollstuhl-Profil (manual/power/scewo) mit
    /// Einstufung und Konformität in Prozent.
    var gintoRatings: [GintoRating] {
        let profiles: [(key: String, label: String)] = [
            ("manual", "Manueller Rollstuhl"),
            ("power", "Elektrorollstuhl"),
            ("scewo", "Scewo BRO"),
        ]
        return profiles.compactMap { profile in
            guard case .object(let dict)? = accessibilityDetails?[profile.key] else { return nil }

            var grade: String?
            if case .string(let value)? = dict["grade"] { grade = value }

            var conformance: Double?
            switch dict["conformance"] {
            case .double(let value):  conformance = value
            case .integer(let value): conformance = Double(value)
            default: break
            }

            guard grade != nil || conformance != nil else { return nil }
            return GintoRating(
                profileKey: profile.key,
                profileLabel: profile.label,
                grade: grade,
                conformancePercent: conformance
            )
        }
    }

    /// Die ginto-Bewertung für den eigenen Rollstuhltyp – nur diese wird
    /// im POI-Detail angezeigt, nicht alle Profile.
    func gintoRating(for wheelchairType: WheelchairType) -> GintoRating? {
        gintoRatings.first { $0.profileKey == wheelchairType.gintoRatingProfileKey }
    }
}

// MARK: - Apple-Karten-Feature

extension POI {
    /// Leichter POI aus einem Apple-Karten-Feature (built-in Point of Interest).
    /// Ohne ginto-/OSM-Zugänglichkeitsdaten – der Status bleibt «unbekannt».
    /// Erlaubt, auch für Apples eigene POIs eine Route zu berechnen und das
    /// gewohnte Detail-Sheet zu öffnen. Als Extension-Initializer, damit der
    /// synthetisierte memberwise-Initializer (SeedData) erhalten bleibt.
    init(appleFeature feature: MapFeature, distanceM: Double = 0) {
        self.id = UUID()
        self.name = feature.title ?? "Ausgewählter Ort"
        self.category = feature.pointOfInterestCategory?.rawValue
        self.latitude = feature.coordinate.latitude
        self.longitude = feature.coordinate.longitude
        self.address = nil
        self.wheelchairAccessible = nil
        self.accessibilityDetails = nil
        self.source = "apple"
        self.distanceM = distanceM
    }

    /// Leichter POI aus einem gespeicherten Ort (saved_places). Wird in der
    /// Suche genutzt, wenn sich der gespeicherte Ort nicht mehr auf einen
    /// geladenen Altstadt-POI auflösen lässt – so lässt er sich trotzdem auf
    /// der Karte ansteuern. Ohne Zugänglichkeitsdaten (Status «unbekannt»).
    init(savedPlace: SavedPlace) {
        self.id = savedPlace.referenceId ?? savedPlace.id
        self.name = savedPlace.displayName
        self.category = nil
        self.latitude = savedPlace.latitude
        self.longitude = savedPlace.longitude
        self.address = nil
        self.wheelchairAccessible = nil
        self.accessibilityDetails = nil
        self.source = "saved"
        self.distanceM = 0
    }
}

/// Eine ginto-Zugänglichkeits-Bewertung für ein Rollstuhl-Profil.
struct GintoRating: Identifiable {
    /// ginto-Profil-Schlüssel in accessibility_details: manual/power/scewo.
    let profileKey: String
    let profileLabel: String
    /// ginto-Einstufung: COMPLETELY / PARTIALLY / BADLY.
    let grade: String?
    /// Erfüllte Zugänglichkeits-Kriterien in Prozent (0–100).
    let conformancePercent: Double?

    var id: String { profileKey }

    var status: POIAccessStatus {
        switch grade?.uppercased() {
        case "COMPLETELY": return .accessible
        case "PARTIALLY":  return .limited
        case "BADLY":      return .notAccessible
        default:           return .unknown
        }
    }

    var gradeLabel: String {
        switch status {
        case .accessible:    return "Vollständig zugänglich"
        case .limited:       return "Teilweise zugänglich"
        case .notAccessible: return "Schlecht zugänglich"
        case .unknown:       return "Keine Einstufung"
        }
    }
}

enum POIAccessStatus {
    case accessible
    case limited
    case notAccessible
    case unknown

    var label: String {
        switch self {
        case .accessible:    return "Zugänglich für dein Profil"
        case .limited:       return "Eingeschränkt zugänglich"
        case .notAccessible: return "Nicht zugänglich"
        case .unknown:       return "Zugänglichkeit unbekannt"
        }
    }

    var shortLabel: String {
        switch self {
        case .accessible:    return "zugänglich für dich"
        case .limited:       return "eingeschränkt"
        case .notAccessible: return "nicht zugänglich"
        case .unknown:       return "unbekannt"
        }
    }

    /// Signalfarbe für grafische Elemente (Marker, Icons). Styleguide §2.3:
    /// die gesättigten Status-Icon-Farben (>= 3:1 Grafikkontrast).
    var tint: Color {
        switch self {
        case .accessible:    return AppColor.Status.openIcon
        case .limited:       return AppColor.Status.limitedIcon
        case .notAccessible: return AppColor.Status.blockedIcon
        case .unknown:       return AppColor.textSecondary
        }
    }

    /// Textfarbe auf der zugehörigen Statusfläche (`fillColor`). AAA auf der Fläche.
    var textColor: Color {
        switch self {
        case .accessible:    return AppColor.Status.openText
        case .limited:       return AppColor.Status.limitedText
        case .notAccessible: return AppColor.Status.blockedText
        case .unknown:       return AppColor.textSecondary
        }
    }

    /// Getönte Hintergrundfläche des Status-Badges.
    var fillColor: Color {
        switch self {
        case .accessible:    return AppColor.Status.openFill
        case .limited:       return AppColor.Status.limitedFill
        case .notAccessible: return AppColor.Status.blockedFill
        case .unknown:       return AppColor.surfaceRaised
        }
    }

    /// SF-Symbol mit Grundform + Symbol (P2: Farbe trägt nie allein Information).
    /// Kreis+Häkchen · Dreieck+Ausrufezeichen · Achteck+Kreuz.
    var symbolName: String {
        switch self {
        case .accessible:    return "checkmark.circle.fill"
        case .limited:       return "exclamationmark.triangle.fill"
        case .notAccessible: return "xmark.octagon.fill"
        case .unknown:       return "questionmark.circle.fill"
        }
    }
}