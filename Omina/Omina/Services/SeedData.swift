// SeedData.swift
// Omina
//
// Gebündelte Erst-Start-Daten für die Altstadt: die statischen Barrieren- und
// POI-Exporte (seed_barriers.json / seed_pois.json) liegen im App-Bundle.
// Zweck am Testtag: Selbst beim allerersten Start OHNE Netz (und ohne bereits
// gefüllten LocalDataStore) zeigt die Karte sofort Daten. Sobald der
// Netz-Abruf durch ist, ersetzen die frischen Supabase-Daten den Seed.
//
// Die Bundle-JSONs stammen direkt aus dem Import-Pipeline-Format (OSM/ginto)
// und weichen vom RPC-Format ab: Koordinaten stecken als WKT `POINT(lng lat)`
// im Feld `location`, es gibt keine `id`/`distance_m`. Dieser Loader parst das
// und bildet stabile `Barrier`/`POI`-Werte, damit Karte, AR und die
// Barrierenlogik unverändert damit arbeiten können.

import Foundation
import CoreLocation
import Supabase

enum SeedData {
    /// Gebündelte Altstadt-Barrieren (einmalig geparst, thread-sicher lazy).
    static let barriers: [Barrier] = decodeBarriers()
    /// Gebündelte Altstadt-POIs (einmalig geparst, thread-sicher lazy).
    static let pois: [POI] = decodePOIs()

    // MARK: - Barrieren

    private struct SeedBarrier: Decodable {
        let type: String
        let subtype: String?
        let value: Double?
        let unit: String?
        let location: String
        let valueSource: String?
        let source: String?
        let sourceId: String?
        let isActive: Bool?

        enum CodingKeys: String, CodingKey {
            case type, subtype, value, unit, location, source
            case valueSource = "value_source"
            case sourceId = "source_id"
            case isActive = "is_active"
        }
    }

    private static func decodeBarriers() -> [Barrier] {
        guard let seeds: [SeedBarrier] = load("seed_barriers") else { return [] }
        return seeds.compactMap { seed in
            guard let type = BarrierType(rawValue: seed.type),
                  let point = parsePoint(seed.location)
            else { return nil }
            let valueSource = seed.valueSource
                .flatMap(ValueSource.init(rawValue:)) ?? .estimated
            return Barrier(
                id: stableUUID("barrier:\(seed.source ?? "osm"):\(seed.sourceId ?? seed.location)"),
                type: type,
                subtype: seed.subtype,
                value: seed.value,
                unit: seed.unit,
                latitude: point.lat,
                longitude: point.lng,
                valueSource: valueSource,
                source: seed.source ?? "osm",
                sourceId: seed.sourceId,
                isActive: seed.isActive ?? true,
                lastVerified: nil
            )
        }
    }

    // MARK: - POIs

    private struct SeedPOI: Decodable {
        let name: String
        let category: String?
        let location: String
        let address: String?
        let wheelchairAccessible: String?
        let accessibilityDetails: [String: AnyJSON]?
        let source: String?
        let sourceId: String?

        enum CodingKeys: String, CodingKey {
            case name, category, location, address, source
            case wheelchairAccessible = "wheelchair_accessible"
            case accessibilityDetails = "accessibility_details"
            case sourceId = "source_id"
        }
    }

    private static func decodePOIs() -> [POI] {
        guard let seeds: [SeedPOI] = load("seed_pois") else { return [] }
        let center = CLLocation(
            latitude: AppConfig.oldTownCenter.latitude,
            longitude: AppConfig.oldTownCenter.longitude
        )
        return seeds.compactMap { seed in
            guard let point = parsePoint(seed.location) else { return nil }
            let distance = CLLocation(latitude: point.lat, longitude: point.lng)
                .distance(from: center)
            return POI(
                id: stableUUID("poi:\(seed.source ?? "ginto"):\(seed.sourceId ?? seed.location)"),
                name: seed.name,
                category: seed.category,
                latitude: point.lat,
                longitude: point.lng,
                address: seed.address,
                wheelchairAccessible: seed.wheelchairAccessible,
                accessibilityDetails: seed.accessibilityDetails,
                source: seed.source ?? "ginto",
                distanceM: distance
            )
        }
    }

    // MARK: - Hilfen

    /// Lädt und decodiert eine gebündelte JSON-Datei. Nested-JSON-Schlüssel in
    /// `accessibility_details` bleiben unangetastet (keine snake_case-Wandlung),
    /// damit POI-Detaildaten (z. B. `ginto_url`) intakt bleiben.
    private static func load<T: Decodable>(_ resource: String) -> T? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Parst WKT `POINT(lng lat)` → (lat, lng).
    private static func parsePoint(_ wkt: String) -> (lat: Double, lng: Double)? {
        guard let open = wkt.firstIndex(of: "("),
              let close = wkt.firstIndex(of: ")")
        else { return nil }
        let inside = wkt[wkt.index(after: open)..<close]
        let parts = inside.split(separator: " ")
        guard parts.count == 2,
              let lng = Double(parts[0]),
              let lat = Double(parts[1])
        else { return nil }
        return (lat, lng)
    }

    /// Erzeugt eine über App-Starts hinweg stabile UUID aus einem Schlüssel
    /// (FNV-1a, zwei gesalzene Durchläufe füllen die 16 Bytes). So bleibt die
    /// Identität einer Seed-Barriere/eines Seed-POI konstant, solange die
    /// frischen Netzdaten sie noch nicht ersetzt haben.
    private static func stableUUID(_ key: String) -> UUID {
        func fnv1a(_ string: String, salt: UInt64) -> UInt64 {
            var hash: UInt64 = 0xcbf29ce484222325 ^ salt
            for byte in string.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
            return hash
        }
        let high = fnv1a(key, salt: 0)
        let low = fnv1a(key, salt: 0x9e37_79b9_7f4a_7c15)
        var bytes = [UInt8]()
        bytes.reserveCapacity(16)
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((high >> UInt64(shift)) & 0xff))
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((low >> UInt64(shift)) & 0xff))
        }
        let uuid = bytes.withUnsafeBytes { $0.load(as: uuid_t.self) }
        return UUID(uuid: uuid)
    }
}
