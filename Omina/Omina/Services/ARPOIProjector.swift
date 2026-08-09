// ARPOIProjector.swift
// Omina
//
// Hält die aktuell in den Bildschirmraum projizierten POIs für den
// AR-POI-Modus. Der ARViewContainer aktualisiert die Liste
// ~8×/Sekunde über arView.project(); das SwiftUI-Overlay positioniert die
// POI-Karten an den gelieferten Punkten.

import Foundation
import CoreGraphics
import Combine

struct ProjectedPOI: Identifiable {
    var id: UUID { poi.id }
    let poi: POI
    let point: CGPoint
}

@MainActor
final class ARPOIProjector: ObservableObject {
    @Published var projected: [ProjectedPOI] = []
}