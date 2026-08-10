// RecentDestinationsStore.swift
// Omina
//
// Merkt sich die letzten Navigationsziele lokal in UserDefaults (offline-first,
// analog zu den letzten Suchen im MapViewModel). Der MapViewModel trägt beim
// Start einer Navigation das Ziel ein, der Homescreen zeigt die Liste an.

import Foundation
import Combine
import CoreLocation

/// Ein Ort, zu dem der User navigiert ist – für die "Letzte Ziele"-Liste.
struct RecentDestination: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let visitedAt: Date
    /// Foto des Ortes für die Bildkarte auf dem Homescreen. Fehlt bei Zielen,
    /// die vor dieser Version gespeichert wurden – dort steht die getönte
    /// Fläche.
    var imageURL: URL?
    /// Der Ort, zu dem navigiert wurde. Damit landet ein Tipp auf dem
    /// Homescreen wieder im richtigen POI-Detail, auch wenn zwei Orte gleich
    /// heissen. Fehlt bei Zielen aus früheren Versionen – dann wird über den
    /// Namen aufgelöst.
    var poiId: UUID?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

@MainActor
final class RecentDestinationsStore: ObservableObject {
    static let shared = RecentDestinationsStore()

    @Published private(set) var destinations: [RecentDestination] = []

    private let storageKey = "omina.recentDestinations"
    private let maxEntries = 10

    private init() {
        load()
    }

    /// Trägt ein Ziel ein (neuestes zuerst). Ein bereits vorhandener Ort mit
    /// gleichem Namen rückt nach vorne statt doppelt zu erscheinen.
    func record(
        name: String,
        latitude: Double,
        longitude: Double,
        imageURL: URL? = nil,
        poiId: UUID? = nil
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        var updated = destinations.filter {
            $0.name.caseInsensitiveCompare(trimmed) != .orderedSame
        }
        updated.insert(
            RecentDestination(
                id: UUID(),
                name: trimmed,
                latitude: latitude,
                longitude: longitude,
                visitedAt: Date(),
                imageURL: imageURL,
                poiId: poiId
            ),
            at: 0
        )
        destinations = Array(updated.prefix(maxEntries))
        save()
    }

    func remove(at offsets: IndexSet) {
        // Ohne SwiftUI-Abhängigkeit (remove(atOffsets:) lebt in SwiftUI):
        // absteigend entfernen, damit die Indizes gültig bleiben.
        for index in offsets.sorted(by: >) where destinations.indices.contains(index) {
            destinations.remove(at: index)
        }
        save()
    }

    // MARK: - Persistenz

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        destinations = (try? decoder.decode([RecentDestination].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(destinations) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}