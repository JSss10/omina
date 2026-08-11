// AppColor.swift
// Omina
//
// Zentrale Farbtokens gemäss Styleguide v1.0 (§02 Farbsystem, §08 Design-Tokens).
// Komponenten referenzieren ausschliesslich diese Tokens, nie Hex-Werte direkt.
// Jedes Token hat eine Light-/Dark-Variante im Asset-Katalog (Assets.xcassets).

import SwiftUI

enum AppColor {

    // MARK: - Basis / Neutral

    /// App-Hintergrund aller Screens: reines Weiss. Light #FFFFFF ·
    /// Dark #1E1830 (nie reines Schwarz). Die einzige Ausnahme sind die
    /// Zustands-Screens, die auf `backgroundMuted` stehen.
    static let backgroundPrimary = Color("BackgroundPrimary")
    /// Karten, Sheets, angehobene Flächen. Light #EDE9FE (Violett 100) ·
    /// Dark #1E1830.
    static let surfaceRaised = Color("SurfaceRaised")
    /// Grundfläche aller Overlays: Bottom-Sheets (Ort, Barriere, Filter,
    /// Suche, Routen, Wegbeschreibung, Wetter) und die Panels, die über der
    /// Karte bzw. dem Kamerabild liegen. Bewusst nicht reines Weiss, damit
    /// sich ein Overlay vom Screen darunter abhebt.
    /// Light #F5F3FF (Violett 50) · Dark #1E1830.
    static let surfaceOverlay = Color("SurfaceOverlay")
    /// Ganzflächiger, violett getönter Hintergrund für Zustands-Screens
    /// (Leer-, Lade- und Fehlerzustände). Light #EDE9FE (Violett 100) ·
    /// Dark #1E1830.
    static let backgroundMuted = Color("BackgroundMuted")
    /// Violett getönte Formen auf dem weissen Grund: Karten, Eingabefelder,
    /// Kapseln und Chips. Light #EDE9FE (Violett 100) · Dark #241D3A.
    static let surfaceTinted = Color("SurfaceTinted")
    /// Fliesstext, Titel. Light #1A1523 (17,9:1) · Dark #F4F1FA.
    static let textPrimary = Color("TextPrimary")
    /// Metadaten, Hinweise. Light #524A5E (8,4:1) · Dark #B3ACC4.
    static let textSecondary = Color("TextSecondary")
    /// Marken-Überschriften (Splash, Intro): Titel im dunklen Violett statt
    /// im neutralen Schwarz. Light #2E1065 (13,9:1) · Dark #DDD6FE.
    static let textBrand = Color("TextBrand")

    // MARK: - Akzent (Leitfarbe Violett)

    /// Buttons, Links, aktive Zustände. Light #5B21B6 (9,0:1) · Dark #C4B5FD.
    static let accentPrimary = Color("AccentPrimary")
    /// Gedrückte Zustände (pressed). Light #4C1D95 (10,9:1) · Dark #DDD6FE.
    static let accentPressed = Color("AccentPressed")
    /// Text/Icon auf AccentPrimary. Light #FFFFFF · Dark #2E1065.
    static let onAccent = Color("OnAccent")
    /// Gedämpfte Akzentfläche für inaktive Primäraktionen (Entwurf: heller
    /// violetter Button mit dunkler Schrift). Light #C4B5FD · Dark #4C1D95.
    static let accentMuted = Color("AccentMuted")
    /// Fokusindikator (3-pt-Ring). Light #6D28D9 (7,1:1) · Dark #C4B5FD.
    static let focusRing = Color("FocusRing")
    /// AR-Scrim-Hintergrund. #2E1065, in beiden Modi (>= 93 % Deckkraft).
    static let scrimAR = Color("ScrimAR")

    // MARK: - Ränder / Linien

    /// Eingabefelder, funktionale Ränder (>= 3:1). Light #8E8699 · Dark #8A80A3.
    static let borderFunctional = Color("BorderFunctional")
    /// Dekorative Trennlinien ohne Funktionsinformation. Light #DDD8E4 · Dark #3D3552.
    static let borderDecorative = Color("BorderDecorative")

    // MARK: - Status-Semantik (§2.3)
    // Jeder Status ist vierfach codiert: Farbe + Form + Symbol + Text (P2).

    enum Status {
        /// «Zugänglich» – Form: Kreis, Symbol: Häkchen.
        static let openText = Color("StatusOpenText")
        static let openFill = Color("StatusOpenFill")
        static let openIcon = Color("StatusOpenIcon")

        /// «Eingeschränkt» – Form: Dreieck, Symbol: Ausrufezeichen.
        static let limitedText = Color("StatusLimitedText")
        static let limitedFill = Color("StatusLimitedFill")
        static let limitedIcon = Color("StatusLimitedIcon")

        /// «Barriere» – Form: Achteck (Stopp-Konvention), Symbol: Kreuz.
        static let blockedText = Color("StatusBlockedText")
        static let blockedFill = Color("StatusBlockedFill")
        static let blockedIcon = Color("StatusBlockedIcon")
    }

    // MARK: - Violett-Palette (Referenzstufen, §2.1)

    enum Violet {
        static let v50 = Color("Violet50")
        static let v100 = Color("Violet100")
        static let v300 = Color("Violet300")
        static let v500 = Color("Violet500")
        static let v600 = Color("Violet600")
        static let v700 = Color("Violet700")
        static let v800 = Color("Violet800")
        static let v900 = Color("Violet900")
        static let v950 = Color("Violet950")
    }
}