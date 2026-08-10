// AppTypography.swift
// Omina
//
// Schrift-Skala gemäss Styleguide v1.0 (§03 Typografie).
// Systemschrift SF Pro über die SwiftUI-Text-Styles, damit Dynamic Type
// bis zur grössten Accessibility-Stufe (AX5) verlustfrei mitskaliert.
// Die pt-Werte in den Kommentaren sind Referenzwerte bei Standard-Textgrösse.

import SwiftUI

enum AppTypography {

    /// Grosstitel · 34/41 · Bold · Screen-Titel.
    static let largeTitle = Font.system(.largeTitle, design: .default, weight: .bold)
    /// Titel 1 · 28/34 · Bold · Abschnittstitel.
    static let title1 = Font.system(.title, design: .default, weight: .bold)
    /// Titel 2 · 22/28 · Semibold · Karten-Titel.
    static let title2 = Font.system(.title2, design: .default, weight: .semibold)
    /// Titel 3 · 20/25 · Semibold · Sheet-Titel, Abschnittsköpfe im Entwurf.
    static let title3 = Font.system(.title3, design: .default, weight: .semibold)
    /// Headline · 17/22 · Semibold · Hervorgehobene Zeile.
    static let headline = Font.system(.headline, design: .default, weight: .semibold)
    /// Body · 17/26 · Regular · Fliesstext (Zeilenhöhe 1,5).
    static let body = Font.system(.body, design: .default, weight: .regular)
    /// Callout · 16/24 · Regular · Sekundäre Hinweise.
    static let callout = Font.system(.callout, design: .default, weight: .regular)
    /// Subheadline · 15/22 · Regular · Kleinste Stufe für essenzielle Inhalte.
    static let subheadline = Font.system(.subheadline, design: .default, weight: .regular)
    /// Fussnote · 13/18 · Regular · Nur ergänzend, nie essenziell.
    static let footnote = Font.system(.footnote, design: .default, weight: .regular)
    /// Monospace-Variante für Messwerte/Codes (SF Mono).
    static let mono = Font.system(.subheadline, design: .monospaced)
}

extension Text {
    /// Fliesstext mit Styleguide-Zeilenhöhe (1,5-fach, WCAG 1.4.8 AAA).
    func bodyStyle() -> some View {
        self.font(AppTypography.body)
            .foregroundColor(AppColor.textPrimary)
            .lineSpacing(6)
    }
}