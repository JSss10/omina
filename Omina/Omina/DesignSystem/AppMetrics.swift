// AppMetrics.swift
// Omina
//
// Masse, Radien und Touch-Ziele gemäss Styleguide v1.0
// (§04 Komponenten, §06 Interaktion). Werte in Points (pt).

import CoreGraphics

enum AppMetrics {

    // MARK: - Touch-Ziele (§6.1)

    enum Touch {
        /// Minimum für alle interaktiven Ziele (WCAG 2.5.5 AAA).
        static let minimum: CGFloat = 44
        /// Primäraktionen und Navigationsentscheide.
        static let primary: CGFloat = 56
        /// Kritische Aktionen im AR-Modus (in Bewegung).
        static let arCritical: CGFloat = 72
        /// Mindestabstand zwischen benachbarten Zielen.
        static let spacing: CGFloat = 8
    }

    // MARK: - Eckenradien

    enum Radius {
        static let chip: CGFloat = 6
        static let field: CGFloat = 12
        static let button: CGFloat = 14
        static let card: CGFloat = 16
        static let sheet: CGFloat = 18
    }

    // MARK: - Schwebende Navigationsleiste (OminaTabBar)

    /// Höhe, die die schwebende Leiste am unteren Rand freihalten muss:
    /// Kapsel (44 pt Trefferfläche + 2 × 8 pt Innenabstand), ihr Abstand zum
    /// Bildschirmrand und etwas Luft, damit die letzte Zeile eines Screens
    /// nicht direkt an der Kapsel klebt.
    static let tabBarInset: CGFloat = 84

    // MARK: - Formularfelder

    enum Field {
        /// Einheitliche Höhe ALLER Eingabefelder in den Formularen. Auch das
        /// Passwortfeld mit der Auge-Schaltfläche (44 pt Trefferfläche) bleibt
        /// damit genau so hoch wie die Felder daneben – vorher wuchs es aus
        /// der Reihe heraus.
        static let height: CGFloat = 56
        /// Senkrechter Innenabstand eines Felds. Zusammen mit der 44-pt-
        /// Schaltfläche ergibt er exakt `height`, deshalb bleibt die Reihe
        /// gleich hoch, ob mit oder ohne Auge.
        static let verticalPadding: CGFloat = (height - Touch.minimum) / 2
        /// Höhe der flachen Zahlenfelder in den Karten (Masse, Fähigkeiten).
        static let compactHeight: CGFloat = 36
    }

    // MARK: - Abstände (4-pt-Raster)

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 40
    }

    // MARK: - Fokusindikator (§4.1, WCAG 2.4.13 AAA)

    enum Focus {
        /// 3-pt-Ring.
        static let ringWidth: CGFloat = 3
        /// 2–3 pt Abstand zwischen Element und Ring.
        static let ringOffset: CGFloat = 3
    }

    // MARK: - AR-Overlays (§05)

    enum AR {
        /// Weltverankerte Labels unterschreiten nie 17 pt auf dem Display.
        static let minLabelSize: CGFloat = 17
        /// Scrim-Mindestdeckkraft (Draussen-Modus: 1.0).
        static let scrimOpacity: Double = 0.93
        /// Helle Kontur um den Scrim.
        static let scrimBorderWidth: CGFloat = 1.5
    }
}