// BarrierFilter.swift
// Omina
//
// Filterzustand der Kartenansicht: welche Barrierentypen auf der Karte
// erscheinen. Wird vom MapViewModel gehalten und vom FilterSheet (M3)
// geändert.
//
// Bewusst OHNE Suchradius: Karte und Homescreen laden immer die ganze
// Altstadt (AppConfig.oldTownCenter/-RadiusM), die Anzeige begrenzt danach
// AppConfig.nearbyDisplayRadiusM. Ein zusätzlicher Filter-Radius hätte
// dazwischen nichts zu steuern.

import Foundation

struct BarrierFilterState: Equatable {
    var enabledTypes: Set<BarrierType>

    static let `default` = BarrierFilterState(
        enabledTypes: Set(BarrierType.allCases)
    )
}
