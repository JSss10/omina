// SavedPlacesService.swift
// Omina
//
// Speichert POIs in der Supabase-Tabelle saved_places (RLS: user-owned).
// Die geography-Spalte akzeptiert WKT-Text ('POINT(lng lat)') via PostgREST.
// Gelesen wird über die RPC saved_places_list (siehe supabase/migrations/saved_places_list.sql),
// die lat/lng explizit liefert.

import Foundation
import Supabase

enum SavedPlacesError: Error {
    case notAuthenticated
}

/// Ein vom User gespeicherter Ort aus saved_places.
struct SavedPlace: Decodable, Identifiable, Equatable {
    let id: UUID
    let name: String?
    let latitude: Double
    let longitude: Double
    let placeType: String?
    let referenceId: UUID?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude
        case placeType = "place_type"
        case referenceId = "reference_id"
        case createdAt = "created_at"
    }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? "Gespeicherter Ort" : trimmed
    }
}

final class SavedPlacesService: @unchecked Sendable {
    static let shared = SavedPlacesService()

    private let client = SupabaseService.shared.client

    func save(poi: POI) async throws {
        guard let userId = AuthService.shared.currentUser?.id else {
            throw SavedPlacesError.notAuthenticated
        }

        let payload: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "name": .string(poi.name),
            "location": .string("POINT(\(poi.longitude) \(poi.latitude))"),
            "place_type": .string("poi"),
            "reference_id": .string(poi.id.uuidString)
        ]

        try await client
            .from("saved_places")
            .insert(payload)
            .execute()
    }

    /// Alle gespeicherten Orte des angemeldeten Users, neueste zuerst.
    func fetchSavedPlaces() async throws -> [SavedPlace] {
        guard AuthService.shared.currentUser != nil else {
            throw SavedPlacesError.notAuthenticated
        }

        let places: [SavedPlace] = try await client
            .rpc("saved_places_list")
            .execute()
            .value

        return places
    }

    /// Entfernt einen gespeicherten Ort (RLS erlaubt nur eigene Zeilen).
    func delete(id: UUID) async throws {
        try await client
            .from("saved_places")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}