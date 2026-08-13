// AssetMedia.swift
// Omina
//
// Hülle für Bilder, die noch nicht vorliegen: Fehlt das Asset, steht ein
// getönter Platzhalter mit SF-Symbol an seiner Stelle, statt dass die Fläche
// leer bleibt oder das Layout springt. So lassen sich Splash und Intro bauen,
// bevor die Illustrationen aus der Gestaltung kommen – wandert die Datei in
// den Asset-Katalog, zeigt derselbe Aufruf ohne Codeänderung das echte Bild.
//
// Styling gemäss Styleguide v1.0 (AppColor, AppMetrics).

import SwiftUI

// MARK: - Bild

/// Bild aus dem Asset-Katalog. Liegt es noch nicht vor, erscheint der
/// Platzhalter mit `placeholderSymbol`.
struct AssetImage: View {
    /// Name des Bildes im Asset-Katalog.
    let name: String
    /// SF-Symbol für den Platzhalter, solange das Bild fehlt.
    let placeholderSymbol: String
    /// Wie das Bild seine Fläche füllt. `.fit` zeigt es vollständig,
    /// `.fill` füllt die Fläche und schneidet Überstehendes ab.
    var contentMode: ContentMode = .fit

    var body: some View {
        if UIImage(named: name) != nil {
            image
        } else {
            AssetPlaceholder(symbol: placeholderSymbol)
        }
    }

    @ViewBuilder
    private var image: some View {
        let base = Image(name)
            .resizable()
            .aspectRatio(contentMode: contentMode)

        // Nur beim Füllen steht Bild über die Fläche hinaus.
        if contentMode == .fill {
            base.clipped()
        } else {
            base
        }
    }
}

// MARK: - Platzhalter

/// Getönte Fläche mit Symbol – die Vertretung für ein Bild, solange es fehlt.
/// Violett 100 als Grund, das Symbol darauf in der Leitfarbe. Rein dekorativ,
/// daher für VoiceOver unsichtbar.
private struct AssetPlaceholder: View {
    let symbol: String

    var body: some View {
        RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
            .fill(AppColor.backgroundMuted)
            .overlay {
                Image(systemName: symbol)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 48, maxHeight: 48)
                    .foregroundStyle(AppColor.accentPrimary)
                    .padding(AppMetrics.Space.l)
            }
            .accessibilityHidden(true)
    }
}

#Preview("Platzhalter") {
    AssetImage(name: "FehltNoch", placeholderSymbol: "figure.stairs")
        .frame(height: 200)
        .padding(AppMetrics.Space.l)
        .background(AppColor.backgroundPrimary)
}