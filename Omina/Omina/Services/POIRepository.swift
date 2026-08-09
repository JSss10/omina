// POIRepository.swift
// Omina
//
// Lädt POIs aus Supabase via RPC pois_within_radius
// (siehe supabase/migrations/pois_within_radius.sql). Freitext-Suche und
// Kategorie-Chips laufen über denselben search-Parameter.

import Foundation
import CoreLocation
import Supabase

final class POIRepository: @unchecked Sendable {
    static let shared = POIRepository()

    private let client = SupabaseService.shared.client

    func fetchPOIs(
        near coordinate: CLLocationCoordinate2D,
        radius: Double,
        search: String? = nil
    ) async throws -> [POI] {
        var params: [String: AnyJSON] = [
            "lat": .double(coordinate.latitude),
            "lng": .double(coordinate.longitude),
            "radius_meters": .double(radius)
        ]
        if let search, !search.isEmpty {
            params["search"] = .string(search)
        }

        // Bei kurzen Netz-Aussetzern am Testtag begrenzt wiederholen.
        return try await withRetry {
            let pois: [POI] = try await client
                .rpc("pois_within_radius", params: params)
                .execute()
                .value
            return pois
        }
    }
}