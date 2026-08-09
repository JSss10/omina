// POIImageTests.swift
// ARMikronavTests
//
// Tests für das Auslesen der POI-Fotos aus accessibility_details.images.
// Das Feld kommt in zwei Formen vor: als reine URL-Strings (ginto-Import)
// und als Objekte mit url/caption/credit (Import aus dem Open-Data-API von
// Zürich Tourismus, scripts/import_zuerich.py). Der Bildnachweis
// muss in beiden Fällen ankommen – die Lizenz der Bildquelle verlangt ihn.

import Testing
import Foundation
@testable import ARMikronav

// Das Test-Target baut ohne MainActor-Standardisolation, die App-Typen
// aber mit. @MainActor hier hält die Aufrufe in dieselbe Isolation.
@MainActor
struct POIImageTests {

    /// Baut einen POI aus dem JSON, das die RPC pois_within_radius liefert.
    private func poi(details: String) throws -> POI {
        let json = """
        {
          "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
          "name": "Café Henrici",
          "category": "coffee",
          "latitude": 47.3726776,
          "longitude": 8.5436817,
          "address": "Niederdorfstrasse 1, 8001 Zürich",
          "wheelchair_accessible": "yes",
          "accessibility_details": \(details),
          "source": "ginto",
          "distance_m": 42.0
        }
        """
        return try JSONDecoder().decode(POI.self, from: Data(json.utf8))
    }

    // MARK: - Objekt-Form (Zürich-Tourismus-Import)

    /// Objekte mit url/caption/credit werden vollständig übernommen.
    @Test func parsesImageObjectsWithCaptionAndCredit() throws {
        let poi = try poi(details: """
        {
          "images": [
            {
              "url": "https://www.zuerich.com/img/henrici.jpg",
              "caption": "Gartenterrasse",
              "credit": "Zürich Tourismus (zuerich.com)"
            },
            { "url": "https://www.zuerich.com/img/henrici-2.jpg" }
          ],
          "image_source": "Zürich Tourismus (zuerich.com)"
        }
        """)

        #expect(poi.images.count == 2)
        #expect(poi.images[0].url.absoluteString == "https://www.zuerich.com/img/henrici.jpg")
        #expect(poi.images[0].caption == "Gartenterrasse")
        #expect(poi.images[0].credit == "Zürich Tourismus (zuerich.com)")
        // Ohne eigenen credit greift image_source.
        #expect(poi.images[1].caption == nil)
        #expect(poi.images[1].credit == "Zürich Tourismus (zuerich.com)")
    }

    /// Der Bildnachweis unter dem Karussell nennt jede Quelle genau einmal.
    @Test func imageCreditListsEverySourceOnce() throws {
        let poi = try poi(details: """
        {
          "images": [
            { "url": "https://example.org/a.jpg", "credit": "Zürich Tourismus" },
            { "url": "https://example.org/b.jpg", "credit": "Zürich Tourismus" },
            { "url": "https://example.org/c.jpg", "credit": "Stadt Zürich" }
          ]
        }
        """)

        #expect(poi.imageCredit == "Zürich Tourismus, Stadt Zürich")
    }

    // MARK: - String-Form (ginto-Import)

    /// Reine URL-Strings bleiben lesbar und erben den Nachweis aus image_source.
    @Test func parsesPlainStringImagesWithFallbackCredit() throws {
        let poi = try poi(details: """
        {
          "images": ["https://example.org/foto.jpg"],
          "image_source": "Zürich Tourismus (zuerich.com)"
        }
        """)

        #expect(poi.images.count == 1)
        #expect(poi.images[0].caption == nil)
        #expect(poi.images[0].credit == "Zürich Tourismus (zuerich.com)")
        #expect(poi.imageCredit == "Zürich Tourismus (zuerich.com)")
    }

    /// Ohne image_source bleibt der Nachweis leer – dann zeigt das Sheet
    /// nur das Foto, keine erfundene Quelle.
    @Test func stringImagesWithoutSourceHaveNoCredit() throws {
        let poi = try poi(details: """
        { "images": ["https://example.org/foto.jpg"] }
        """)

        #expect(poi.images.count == 1)
        #expect(poi.images[0].credit == nil)
        #expect(poi.imageCredit == nil)
    }

    // MARK: - Robustheit

    /// Einträge ohne url oder mit falschem Typ werden übersprungen,
    /// der Rest der Liste bleibt nutzbar.
    @Test func skipsEntriesWithoutUsableURL() throws {
        let poi = try poi(details: """
        {
          "images": [
            { "caption": "Foto ohne URL" },
            42,
            { "url": "https://example.org/gut.jpg" }
          ]
        }
        """)

        #expect(poi.images.count == 1)
        #expect(poi.images[0].url.absoluteString == "https://example.org/gut.jpg")
    }

    /// POIs ohne Bilder (ginto/OSM ohne Zürich-Tourismus-Treffer) liefern
    /// eine leere Liste – das Karussell entfällt dann komplett.
    @Test func poiWithoutImagesHasEmptyList() throws {
        let withoutKey = try poi(details: """
        { "manual": { "grade": "COMPLETELY", "conformance": 100 } }
        """)
        #expect(withoutKey.images.isEmpty)
        #expect(withoutKey.imageCredit == nil)

        let withNullDetails = try poi(details: "null")
        #expect(withNullDetails.images.isEmpty)
    }
}