// POICategory.swift
// Omina
//
// Mapping zwischen den deutschen Kategorie-Chips der UI, den englischen
// Kategorie-Keys aus poi_accessibility (ginto/OSM, z.B. "coffee",
// "public_toilets") und passenden SF-Symbols für die kreisförmigen
// POI-Marker in Karte und AR-Modus.

import Foundation

/// Ein Kategorie-Chip der UI: deutsches Label plus die exakten
/// ginto-Kategorie-Keys aus poi_accessibility, die er abdeckt.
struct POICategoryChip: Identifiable, Hashable {
    let label: String
    let keys: Set<String>

    var id: String { label }

    /// SF-Symbol des Chips (über den ersten Kategorie-Key aufgelöst).
    var symbol: String {
        POICategory.symbol(for: keys.sorted().first)
    }

    /// Exaktes Matching gegen den DB-Kategorie-Key eines POI.
    func matches(category: String?) -> Bool {
        guard let category else { return false }
        return keys.contains(category.lowercased())
    }
}

enum POICategory {
    /// Alle verfügbaren Kategorien der ginto-API als Chips (deutsche Labels),
    /// gruppiert nach Themen und nach Häufigkeit/Relevanz sortiert. Die Keys
    /// decken sämtliche Kategorie-Werte aus dem ginto-Import ab.
    static let chips: [POICategoryChip] = [
        POICategoryChip(label: "Restaurant", keys: ["restaurant"]),
        POICategoryChip(label: "Café", keys: ["coffee", "bakery"]),
        POICategoryChip(label: "WC", keys: ["public_toilets"]),
        POICategoryChip(label: "Fast Food", keys: ["fastfood"]),
        POICategoryChip(label: "Bar & Club", keys: ["bar", "club", "music"]),
        POICategoryChip(label: "Gastronomie", keys: ["gastronomy_other"]),
        POICategoryChip(label: "Haltestelle", keys: ["bus_stop"]),
        POICategoryChip(label: "Bahnhof & Schiff", keys: ["train_station", "ship_landing"]),
        POICategoryChip(label: "Parkieren", keys: ["parking_lot", "multi_storey_car_park"]),
        POICategoryChip(label: "Hotel", keys: ["hotel"]),
        POICategoryChip(label: "Museum", keys: ["museum"]),
        POICategoryChip(label: "Sehenswürdigkeit", keys: ["landmark", "lookout", "religious_institution"]),
        POICategoryChip(label: "Kultur & Bühne", keys: ["theatre", "cinema", "concert_hall", "congress_center"]),
        POICategoryChip(label: "Apotheke & Drogerie", keys: ["pharmacy", "drugstore"]),
        POICategoryChip(label: "Gesundheit", keys: ["doctors_practice", "dentist", "massage"]),
        POICategoryChip(label: "Lebensmittel", keys: ["grocery_store", "grocery_other"]),
        POICategoryChip(label: "Shopping", keys: [
            "fashion", "shopping_other", "department_store", "mall",
            "electronics", "furniture", "toys", "bookstore",
        ]),
        POICategoryChip(label: "Bank & Post", keys: ["bank", "atm", "post"]),
        POICategoryChip(label: "Coiffeur", keys: ["hairdresser"]),
        POICategoryChip(label: "Dienstleistungen", keys: [
            "services_other", "travel_agency", "tourist_information",
        ]),
        POICategoryChip(label: "Verwaltung", keys: ["administration", "community_center"]),
        POICategoryChip(label: "Bildung", keys: ["school", "higher_education", "education_other"]),
        POICategoryChip(label: "Freizeit & Bad", keys: ["activities_other", "playground", "park", "bath"]),
    ]

    /// Kategorie-Chips (deutsche Labels) in fixer Reihenfolge für die Filter
    /// in der Suche (SearchSheet) und im AR-Modus.
    static var chipLabels: [String] { chips.map(\.label) }

    /// Chip zum Label (case-insensitiv), nil für Freitext.
    static func chip(forLabel label: String) -> POICategoryChip? {
        let normalized = label.trimmingCharacters(in: .whitespaces)
        return chips.first { $0.label.caseInsensitiveCompare(normalized) == .orderedSame }
    }

    /// Matcht ein POI-Kategorie-Key den Chip mit diesem Label?
    static func chip(_ label: String, matches category: String?) -> Bool {
        chip(forLabel: label)?.matches(category: category) ?? false
    }

    /// SF-Symbol für einen Kategorie-Chip (deutsches Label), z. B. für die
    /// Filter-Chips in der Suche.
    static func symbol(forChip chipLabel: String) -> String {
        if let chip = chip(forLabel: chipLabel) {
            return chip.symbol
        }
        return symbol(for: searchTerm(forChip: chipLabel))
    }

    /// Deutsche Freitext-Begriffe → englischer DB-Suchbegriff für die RPC
    /// `pois_within_radius` (ILIKE über Name UND Kategorie). Ohne das Mapping
    /// würden deutsche Eingaben wie "wc" oder "apotheke" (fast) nichts finden.
    private static let freeTextSearchTerms: [String: String] = [
        "Café": "coffee",
        "Kaffee": "coffee",
        "Bäckerei": "bakery",
        "Restaurant": "restaurant",
        "WC": "toilet",        // matcht "public_toilets"
        "Toilette": "toilet",
        "Apotheke": "pharmacy",
        "Drogerie": "drugstore",
        "Haltestelle": "bus_stop",
        "Bahnhof": "train_station",
        "Parkplatz": "parking",
        "Parkhaus": "car_park",
        "Hotel": "hotel",
        "Museum": "museum",
        "Theater": "theatre",
        "Kino": "cinema",
        "Konzert": "concert",
        "Bank": "bank",
        "Post": "post",
        "Coiffeur": "hairdresser",
        "Friseur": "hairdresser",
        "Schule": "school",
        "Bad": "bath",
        "Spielplatz": "playground",
        "Arzt": "doctors_practice",
        "Zahnarzt": "dentist",
        "Lebensmittel": "grocery",
        "Mode": "fashion",
        "Buchhandlung": "bookstore",
        "Sehenswürdigkeit": "landmark",
        "Verwaltung": "administration",
    ]

    /// Case-insensitiv, damit auch Freitext-Eingaben wie "wc" oder "café"
    /// auf den DB-Kategorie-Begriff gemappt werden.
    static func searchTerm(forChip chip: String) -> String {
        let normalized = chip.trimmingCharacters(in: .whitespaces)
        let match = freeTextSearchTerms.first {
            $0.key.caseInsensitiveCompare(normalized) == .orderedSame
        }
        return match?.value ?? normalized
    }

    /// SF-Symbol zur DB-Kategorie (contains-Matching, damit Varianten wie
    /// "gastronomy_other" oder "shopping_other" mit abgedeckt sind).
    static func symbol(for category: String?) -> String {
        let key = category?.lowercased() ?? ""
        switch true {
        case key.contains("restaurant"), key.contains("gastronomy"):
            return "fork.knife"
        case key.contains("fastfood"):
            return "takeoutbag.and.cup.and.straw.fill"
        case key.contains("coffee"), key.contains("cafe"), key.contains("bakery"):
            return "cup.and.saucer.fill"
        case key.contains("bar"), key.contains("club"), key.contains("music"):
            return "wineglass.fill"
        case key.contains("toilet"):
            return "toilet.fill"
        case key.contains("pharmacy"), key.contains("drugstore"):
            return "cross.case.fill"
        case key.contains("doctor"), key.contains("dentist"), key.contains("massage"):
            return "stethoscope"
        case key.contains("hotel"):
            return "bed.double.fill"
        case key.contains("bus"), key.contains("station"), key.contains("stop"),
             key.contains("ship"):
            return "bus.fill"
        case key.contains("parking"), key.contains("car_park"):
            return "parkingsign"
        case key.contains("grocery"), key.contains("market"):
            return "basket.fill"
        case key.contains("museum"), key.contains("landmark"), key.contains("lookout"),
             key.contains("administration"), key.contains("community"),
             key.contains("religious"):
            return "building.columns.fill"
        case key.contains("theatre"), key.contains("cinema"), key.contains("concert"),
             key.contains("congress"):
            return "theatermasks.fill"
        case key.contains("hairdresser"):
            return "scissors"
        case key.contains("bank"), key.contains("atm"):
            return "banknote.fill"
        case key.contains("post"):
            return "envelope.fill"
        case key.contains("education"), key.contains("school"):
            return "graduationcap.fill"
        case key.contains("fashion"), key.contains("shopping"),
             key.contains("bookstore"), key.contains("department_store"),
             key.contains("mall"), key.contains("electronics"),
             key.contains("furniture"), key.contains("toys"):
            return "bag.fill"
        case key.contains("services"), key.contains("travel"), key.contains("tourist"):
            return "info.circle.fill"
        case key.contains("bath"):
            return "drop.fill"
        case key.contains("playground"), key.contains("activities"):
            return "figure.play"
        case key.contains("park"):
            return "tree.fill"
        default:
            return "mappin"
        }
    }
}

extension POI {
    /// Kategorie-Icon für die kreisförmigen Marker.
    var categorySymbol: String {
        POICategory.symbol(for: category)
    }
}