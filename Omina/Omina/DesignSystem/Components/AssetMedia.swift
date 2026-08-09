// AssetMedia.swift
// Omina
//
// Hüllen für Bilder und Videos, die noch nicht vorliegen: Fehlt das Asset
// bzw. die Bundle-Ressource, steht ein getönter Platzhalter mit SF-Symbol an
// seiner Stelle, statt dass die Fläche leer bleibt oder das Layout springt.
// So lassen sich Splash und Intro bauen, bevor die Illustrationen und das
// Erklärvideo aus der Gestaltung kommen – wenn die Dateien in den
// Asset-Katalog bzw. ins Bundle wandern, zeigen dieselben Aufrufe ohne
// Codeänderung das echte Medium.
//
// Styling gemäss Styleguide v1.0 (AppColor, AppMetrics).

import AVKit
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

// MARK: - Video

/// Video aus dem App-Bundle. Fehlt die Datei, erscheint der Platzhalter –
/// der Slide bleibt damit auch ohne Video vollständig bedienbar.
struct AssetVideo: View {
    /// Dateiname der Bundle-Ressource, ohne Endung.
    let resource: String
    /// Dateiendung der Ressource.
    var fileExtension: String = "mp4"
    /// SF-Symbol für den Platzhalter, solange das Video fehlt.
    var placeholderSymbol: String = "play.rectangle"
    /// Beschriftung für VoiceOver.
    var accessibilityLabel: String = "Erklärvideo"

    /// Der Player entsteht erst beim Einblenden und überlebt das Neuzeichnen
    /// des Slides – sonst würde jede Änderung das Video zurücksetzen.
    @State private var player: AVPlayer?

    private var url: URL? {
        Bundle.main.url(forResource: resource, withExtension: fileExtension)
    }

    var body: some View {
        if let url {
            VideoPlayer(player: player)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: AppMetrics.Radius.card,
                        style: .continuous
                    )
                )
                .accessibilityLabel(accessibilityLabel)
                .onAppear {
                    if player == nil {
                        player = AVPlayer(url: url)
                    }
                }
                // Beim Weiterblättern läuft sonst der Ton im Hintergrund weiter.
                .onDisappear { player?.pause() }
        } else {
            AssetPlaceholder(symbol: placeholderSymbol)
        }
    }
}

// MARK: - Platzhalter

/// Getönte Fläche mit Symbol – die gemeinsame Vertretung für Bild und Video,
/// solange das Medium fehlt. Rein dekorativ, daher für VoiceOver unsichtbar.
private struct AssetPlaceholder: View {
    let symbol: String

    var body: some View {
        RoundedRectangle(cornerRadius: AppMetrics.Radius.card, style: .continuous)
            .fill(AppColor.backgroundMuted)
            .overlay {
                Image(systemName: symbol)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 64, maxHeight: 64)
                    .foregroundStyle(AppColor.accentPrimary.opacity(0.4))
                    .padding(AppMetrics.Space.l)
            }
            .accessibilityHidden(true)
    }
}

#Preview("Platzhalter") {
    VStack(spacing: AppMetrics.Space.l) {
        AssetImage(name: "FehltNoch", placeholderSymbol: "figure.stairs")
            .frame(height: 200)
        AssetVideo(resource: "FehltNoch")
            .frame(height: 200)
    }
    .padding(AppMetrics.Space.l)
    .background(AppColor.backgroundPrimary)
}