// POIPlaceInfoTests.swift
// OminaTests
//
// Tests für die Angaben, die scripts/import_zuerich.py aus dem Open-Data-API
// von Zürich Tourismus in accessibility_details schreibt: Öffnungszeiten
// (Anzeigezeilen und strukturiert), Telefon, Beschreibung, Quellenangabe.
// Kennt das API einen POI nicht, müssen alle Felder leer bleiben – nur dann
// zeigt das Detail-Sheet seine Platzhalter.

import Testing
import Foundation
@testable import Omina

// Das Test-Target baut ohne MainActor-Standardisolation, die App-Typen
// aber mit. @MainActor hier hält die Aufrufe in dieselbe Isolation.
@MainActor
struct POIPlaceInfoTests {

    /// Fester Kalender in UTC, damit der Wochentag im Test nicht von der
    /// Zeitzone des Rechners abhängt.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: iso)!
    }

    private func poi(details: String) throws -> POI {
        let json = """
        {
          "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
          "name": "Rathaus Café",
          "category": "coffee",
          "latitude": 47.3719,
          "longitude": 8.5429,
          "address": "Limmatquai 55, 8001 Zürich",
          "wheelchair_accessible": "limited",
          "accessibility_details": \(details),
          "source": "ginto",
          "distance_m": 120.0
        }
        """
        return try JSONDecoder().decode(POI.self, from: Data(json.utf8))
    }

    /// Ein POI, wie ihn der Import nach einem Treffer im API hinterlässt.
    private func matchedPOI() throws -> POI {
        try poi(details: """
        {
          "opening_hours": ["Mo-Fr 09:00-18:00", "Sa 10:00-16:00"],
          "opening_hours_spec": [
            { "days": [1, 2, 3, 4, 5], "opens": "09:00", "closes": "18:00" },
            { "days": [6], "opens": "10:00", "closes": "16:00" }
          ],
          "phone": "+41 44 251 23 45",
          "description": "Café im Rathaus mit Blick auf die Limmat.",
          "website": "https://www.rathaus-cafe.ch",
          "zuerich_url": "https://www.zuerich.com/de/besuchen/rathaus-cafe",
          "info_source": "Zürich Tourismus (zuerich.com)"
        }
        """)
    }

    // MARK: - Öffnungszeiten

    /// Die Anzeigezeilen kommen in der Reihenfolge des API an.
    @Test func readsOpeningHourLines() throws {
        #expect(try matchedPOI().openingHours == ["Mo-Fr 09:00-18:00", "Sa 10:00-16:00"])
    }

    /// Auch eine einzelne Zeile statt einer Liste wird gelesen.
    @Test func readsSingleOpeningHourLine() throws {
        let poi = try poi(details: #"{ "opening_hours": "täglich 06:00-22:00" }"#)
        #expect(poi.openingHours == ["täglich 06:00-22:00"])
    }

    /// Montag liegt im Bereich 1–5, also gelten 09:00–18:00.
    @Test func highlightsTodayFromSpecification() throws {
        let monday = date("2026-08-10T12:00:00Z")
        #expect(try matchedPOI().openingHoursToday(monday, calendar: utc) == "09:00–18:00")
    }

    /// Samstag hat einen eigenen Eintrag – der Wochentag muss exakt treffen.
    @Test func picksTheEntryOfTheCurrentWeekday() throws {
        let saturday = date("2026-08-15T12:00:00Z")
        #expect(try matchedPOI().openingHoursToday(saturday, calendar: utc) == "10:00–16:00")
    }

    /// Sonntag kommt in keinem Eintrag vor: geschlossen, also keine Zeile.
    @Test func noHoursOnADayWithoutEntry() throws {
        let sunday = date("2026-08-09T12:00:00Z")
        #expect(try matchedPOI().openingHoursToday(sunday, calendar: utc) == nil)
    }

    /// Mehrere Zeitfenster am selben Tag (Mittag und Abend) werden zusammengefasst.
    @Test func joinsSeveralWindowsOfTheSameDay() throws {
        let poi = try poi(details: """
        {
          "opening_hours_spec": [
            { "days": [3], "opens": "11:30", "closes": "14:00" },
            { "days": [3], "opens": "18:00", "closes": "23:00" }
          ]
        }
        """)
        let wednesday = date("2026-08-12T12:00:00Z")
        #expect(poi.openingHoursToday(wednesday, calendar: utc) == "11:30–14:00, 18:00–23:00")
    }

    /// Ohne strukturierte Fassung gibt es keine Heute-Zeile, die Anzeigezeilen
    /// bleiben aber nutzbar.
    @Test func withoutSpecificationOnlyTheLinesRemain() throws {
        let poi = try poi(details: #"{ "opening_hours": ["Mo-So 10:00-22:00"] }"#)
        #expect(poi.openingHours == ["Mo-So 10:00-22:00"])
        #expect(poi.openingHoursToday(date("2026-08-10T12:00:00Z"), calendar: utc) == nil)
    }

    // MARK: - Kontakt und Quelle

    /// Der tel:-Link enthält nur Ziffern und das führende Plus.
    @Test func buildsPhoneLinkWithoutSpaces() throws {
        let poi = try matchedPOI()
        #expect(poi.phoneNumber == "+41 44 251 23 45")
        #expect(poi.phoneURL?.absoluteString == "tel:+41442512345")
    }

    @Test func readsDescriptionSourceAndLinks() throws {
        let poi = try matchedPOI()
        #expect(poi.placeDescription == "Café im Rathaus mit Blick auf die Limmat.")
        #expect(poi.infoCredit == "Zürich Tourismus (zuerich.com)")
        #expect(poi.zuerichURL?.host == "www.zuerich.com")
        // websiteRow zeigt die Seite des Ortes, nicht die zuerich.com-Seite.
        #expect(poi.websiteURL?.absoluteString == "https://www.rathaus-cafe.ch")
    }

    // MARK: - Kein Treffer im API

    /// POIs, die das API nicht kennt, behalten ihre ginto-Daten und liefern
    /// zu allen Zusatzangaben nichts – das Sheet zeigt dort Platzhalter.
    @Test func poiWithoutMatchStaysEmpty() throws {
        let poi = try poi(details: """
        { "manual": { "grade": "PARTIALLY", "conformance": 76 } }
        """)

        #expect(poi.openingHours.isEmpty)
        #expect(poi.openingHoursToday(date("2026-08-10T12:00:00Z"), calendar: utc) == nil)
        #expect(poi.phoneNumber == nil)
        #expect(poi.phoneURL == nil)
        #expect(poi.placeDescription == nil)
        #expect(poi.zuerichURL == nil)
        #expect(poi.infoCredit == nil)
        #expect(poi.images.isEmpty)
    }
}