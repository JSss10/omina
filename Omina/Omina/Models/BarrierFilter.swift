// BarrierFilter.swift
// Omina
//
// Filterzustand der Kartenansicht: aktive Barrierentypen + Suchradius.
// Wird vom MapViewModel gehalten und vom FilterSheet (M3) geändert.

import Foundation

struct BarrierFilterState: Equatable {
    var enabledTypes: Set<BarrierType>
    var radius: Double

    static let `default` = BarrierFilterState(
        enabledTypes: Set(BarrierType.allCases),
        radius: AppConfig.defaultBarrierRadius
    )

    static let minRadius: Double = 100
    static let maxRadius: Double = 1000
    static let radiusStep: Double = 50
}