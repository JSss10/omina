// AppSymbol.swift
// Omina
//
// SF-Symbole im aktiven Zustand: Ein angetipptes bzw. ausgewähltes Icon steht
// gefüllt ("house" → "house.fill"), im Ruhezustand in der Konturvariante. So
// trägt die Auswahl neben Farbe und Fläche auch die Form – sie ist damit nicht
// allein über die Farbe codiert (Styleguide §2.3, P2).
//
// Nicht jedes Symbol hat eine gefüllte Fassung (z. B. "camera.viewfinder").
// Dann bleibt es beim Ausgangssymbol, statt ein fehlendes Bild zu zeigen.

import SwiftUI

enum AppSymbol {

    /// Symbolname für den gegebenen Zustand: ausgewählt die gefüllte Variante,
    /// sonst das übergebene Symbol.
    static func name(_ symbol: String, isSelected: Bool) -> String {
        isSelected ? filled(symbol) : symbol
    }

    /// Gefüllte Variante eines SF-Symbols, sofern das System sie kennt.
    /// Bereits gefüllte Symbole ("toilet.fill") bleiben unverändert.
    static func filled(_ symbol: String) -> String {
        guard !symbol.hasSuffix(".fill") else { return symbol }
        let candidate = symbol + ".fill"
        return UIImage(systemName: candidate) == nil ? symbol : candidate
    }
}
