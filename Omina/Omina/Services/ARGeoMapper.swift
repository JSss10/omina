// ARGeoMapper.swift
// Omina
//
// Wandelt eine GPS-Koordinate in eine AR-Welt-Position relativ zu einem
// Ursprungspunkt um. Funktioniert für ARWorldTrackingConfiguration mit
// `worldAlignment = .gravityAndHeading`, wo:
//   +X = East, +Y = Up, -Z = North (true north).
//
// Verwendet eine Flach-Erde-Näherung – ausreichend genau für die <1 km Reichweite
// rund um den Userstandort (Fehler << 1 m).

import Foundation
import CoreLocation
import simd

enum ARGeoMapper {
    private static let metersPerDegreeLatitude: Double = 111_320

    static func arPosition(
        of target: CLLocationCoordinate2D,
        relativeTo origin: CLLocationCoordinate2D,
        height: Float = 0
    ) -> SIMD3<Float> {
        let originLatRad = origin.latitude * .pi / 180
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(originLatRad)

        let northMeters = (target.latitude - origin.latitude) * metersPerDegreeLatitude
        let eastMeters = (target.longitude - origin.longitude) * metersPerDegreeLongitude

        return SIMD3<Float>(
            Float(eastMeters),
            height,
            -Float(northMeters)
        )
    }
}