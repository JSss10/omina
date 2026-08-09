// MKPolyline+Coordinates.swift
// Omina
//
// MapKit gibt die Punkte einer Polyline nur über einen C-Puffer heraus; diese
// Hilfe liefert sie als gewöhnliches Swift-Array, damit Karte (MapPolyline)
// und AR-Rendering dieselbe Geometrie verwenden können.

import Foundation
import MapKit
import CoreLocation

extension MKPolyline {
    /// Alle Koordinaten des Polylines als Array.
    func coordinateList() -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: pointCount
        )
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
