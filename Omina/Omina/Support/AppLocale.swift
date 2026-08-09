// AppLocale.swift
// Omina
//
// Der Prototyp ist bewusst nur auf Deutsch (Schweiz). Direkte
// `Date().formatted(…)`-Aufrufe erzeugen sofort einen String und
// berücksichtigen die SwiftUI-Environment-Locale NICHT – sie nutzen
// `Locale.current` (Gerätesprache). Damit Datumsangaben unabhängig von der
// Gerätesprache immer auf Deutsch erscheinen, wird diese feste Locale
// explizit an die FormatStyles übergeben (`.locale(.appGerman)`).

import Foundation

extension Locale {
    static let appGerman = Locale(identifier: "de_CH")
}